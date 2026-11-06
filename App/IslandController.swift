import ActivityKit
import Foundation
import SwiftUI

/// The one Live Activity: the sprite "at rest" while standby keeps the App alive in the background.
///
/// The state and the line come from the server on the ordinary poll; this only shows them. Every
/// update sets staleDate = now + 5 min, so if the App is killed the island still stays (iOS keeps it)
/// but turns grey and says so: that is the honest "background dropped" signal, not a fake presence.
@MainActor
final class IslandController {
    private static let savedKey = "island.server.v1"
    /// In the foreground the island is refreshed at most this often.
    private static let presenceEvery: TimeInterval = 60
    /// A presence update is good for this long; after it the extension draws the grey sprite.
    private static let staleAfter: TimeInterval = 300
    /// Back in the App, the island is left alone for a minute, then ended.
    private static let foregroundGrace: TimeInterval = 60
    private static let previewSeconds: TimeInterval = 10

    typealias Inputs = () -> (standbyEnabled: Bool, standbyPlaying: Bool)

    private var activity: Activity<IslandAttributes>?
    private var serverState: String
    private var serverLine: String
    private var hidden = false
    private var lastPush = Date.distantPast
    private var lastSent: IslandAttributes.ContentState?
    private var scene: ScenePhase = .inactive
    private var foregroundSince: Date? = nil
    private var preview: (state: String, until: Date)?
    private var timerTask: Task<Void, Never>?
    private var requesting = false
    private let inputs: Inputs
    private let log: (String) -> Void
    /// "presence", "none", "disabled", or the last error ("error 域:码"); for the App's status screen.
    private(set) var status = "none"

    init(inputs: @escaping Inputs, log: @escaping (String) -> Void) {
        self.inputs = inputs
        self.log = log
        let saved = UserDefaults.standard.stringArray(forKey: Self.savedKey) ?? []
        serverState = saved.first ?? SpriteState.calm.rawValue
        serverLine = saved.count > 1 ? saved[1] : "在呢。"
        // An activity left from before the App was killed: keep one, end any others.
        let existing = Activity<IslandAttributes>.activities
        activity = existing.first
        for extra in existing.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: inputs

    /// From each poll answer. A missing `island` keeps the last state.
    func serverUpdate(_ info: IslandInfo?) {
        if let info {
            hidden = info.hide == true
            if let state = info.state, SpriteState(rawValue: state) != nil,
               let line = info.line, !line.isEmpty {
                serverState = state
                serverLine = String(line.prefix(30))
                UserDefaults.standard.set([serverState, serverLine], forKey: Self.savedKey)
            }
        }
        refresh()
    }

    func setScene(_ phase: ScenePhase) {
        let wasActive = scene == .active
        scene = phase
        if phase == .active {
            if !wasActive { foregroundSince = Date() }
            // Re-check once the minute in the foreground is up.
            timerTask?.cancel()
            timerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((Self.foregroundGrace + 1) * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        } else {
            foregroundSince = nil
        }
        refresh()
    }

    /// Show this sprite for 10 s, whatever the App is doing (then swipe home to see it).
    func showPreview(_ state: String) {
        guard SpriteState(rawValue: state) != nil else { return }
        preview = (state, Date().addingTimeInterval(Self.previewSeconds))
        refresh()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.previewSeconds + 0.2) * 1_000_000_000))
            self?.refresh()
        }
    }

    // MARK: deciding

    private enum Want { case end, keep, show(IslandAttributes.ContentState, immediate: Bool) }

    private func presence(_ state: String) -> IslandAttributes.ContentState {
        IslandAttributes.ContentState(state: state, line: serverLine)
    }

    private func decide(standbyEnabled: Bool, standbyPlaying: Bool, now: Date) -> Want {
        if let preview, preview.until > now { return .show(presence(preview.state), immediate: true) }
        if preview != nil {
            preview = nil
            lastPush = .distantPast           // back from the preview at once
        }
        if hidden || !standbyEnabled { return .end }
        if scene == .active {
            if let since = foregroundSince, now.timeIntervalSince(since) > Self.foregroundGrace { return .end }
            // Just back in the App: leave the island as it is for the first minute.
            return activity == nil ? .keep : .show(presence(serverState), immediate: false)
        }
        // Inactive or background: only standby keeps the App alive; without it the island goes stale.
        return standbyPlaying ? .show(presence(serverState), immediate: false) : .keep
    }

    func refresh() {
        let now = Date()
        let live = inputs()
        switch decide(standbyEnabled: live.standbyEnabled, standbyPlaying: live.standbyPlaying, now: now) {
        case .keep:
            return
        case .end:
            guard let current = activity else { status = "none"; return }
            activity = nil
            lastSent = nil
            status = "none"
            log("island end \(Self.short(current.id)) scene=\(scene) hidden=\(hidden)")
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        case let .show(content, immediate):
            // A stale activity (past its staleDate) is still the one on screen: update it, never add a second.
            if let current = activity, current.activityState == .active || current.activityState == .stale {
                // Foreground: at most once a minute. Away from the App every poll answer (about one a
                // minute) renews the staleDate, so a grey island means the answers stopped.
                if !immediate && scene == .active && now.timeIntervalSince(lastPush) < Self.presenceEvery { return }
                push(content, to: current, now: now)
            } else {
                if let current = activity {
                    log("island replace \(Self.short(current.id)) state=\(String(describing: current.activityState))")
                }
                start(content, now: now)
            }
        }
    }

    private static func short(_ id: String) -> String { String(id.prefix(8)) }

    private func push(_ content: IslandAttributes.ContentState, to current: Activity<IslandAttributes>, now: Date) {
        lastPush = now
        lastSent = content
        status = "presence"
        let update = ActivityContent(state: content, staleDate: now.addingTimeInterval(Self.staleAfter))
        log("island push \(Self.short(current.id)) \(content.state) scene=\(scene) was=\(String(describing: current.activityState))")
        Task { await current.update(update) }
    }

    private func start(_ content: IslandAttributes.ContentState, now: Date) {
        guard !requesting else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "disabled"; return }
        activity = nil
        do {
            // iOS only lets the App start an activity while it is visible; the moment of leaving the App
            // (inactive) still counts. Started later from the background this throws, and the island
            // waits for the next time the user leaves the App.
            let started = try Activity.request(
                attributes: IslandAttributes(),
                content: ActivityContent(state: content, staleDate: now.addingTimeInterval(Self.staleAfter)),
                pushType: nil)
            activity = started
            lastPush = now
            lastSent = content
            status = "presence"
            log("island start \(Self.short(started.id)) \(content.state) scene=\(scene)")
        } catch {
            let failure = error as NSError
            status = "error \(failure.domain):\(failure.code)"
            log("island start failed \(failure.domain):\(failure.code) scene=\(scene)")
        }
    }
}
