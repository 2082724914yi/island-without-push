import Foundation

/// When the App may poll from the background, and when the silent audio should play. Pure logic, so
/// it compiles and runs under plain `swiftc` on the CI runner (see Tests/StandbyTests.swift).
struct StandbyState {
    enum Visibility { case active, inactive, background }
    private(set) var visibility: Visibility = .inactive
    var leaseExpired = false

    /// Returns true when a short background lease should begin. Only an actual foreground visit
    /// renews eligibility, never a transient inactive event (control centre, a system alert).
    mutating func transition(to next: Visibility) -> Bool {
        let enteringBackground = next == .background && visibility != .background
        visibility = next
        if next == .active { leaseExpired = false }
        return enteringBackground && !leaseExpired
    }

    /// In the background the poll may only run while the lease or the audio keeps the process alive.
    func canPoll(lease: Bool, audio: Bool) -> Bool {
        visibility != .background || lease || audio
    }

    /// Start the audio when leaving the active state, so it is already running before iOS would
    /// suspend the App; an active App does not need it. `blocked` covers an audio interruption.
    func shouldPlay(enabled: Bool, blocked: Bool) -> Bool {
        enabled && !blocked && visibility != .active
    }
}

#if canImport(UIKit)
import AVFAudio
import SwiftUI
import UIKit

/// Keeps the App alive in the background with one second of silence looped by AVAudioPlayer under the
/// `audio` background mode, plus a short background-task lease for the moments before it starts.
@MainActor
final class Standby {
    private(set) var state = StandbyState()
    private var lease: UIBackgroundTaskIdentifier = .invalid
    private var player: AVAudioPlayer?
    var onExpiration: (() -> Void)?
    var isPlaying: Bool { player?.isPlaying == true }
    var hasLease: Bool { lease != .invalid }

    func setScenePhase(_ phase: ScenePhase) {
        let next: StandbyState.Visibility
        switch phase {
        case .active: next = .active
        case .background: next = .background
        default: next = .inactive
        }
        let begin = state.transition(to: next)
        if next == .active { endLease() }
        if begin { beginLease() }
    }

    private func beginLease() {
        guard lease == .invalid else { return }
        lease = UIApplication.shared.beginBackgroundTask(withName: "Finish background poll") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.state.leaseExpired = true
                self.endLease()
                self.onExpiration?()
            }
        }
    }

    func endLease() {
        if lease != .invalid { UIApplication.shared.endBackgroundTask(lease); lease = .invalid }
    }

    func start() throws {
        guard !isPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers: her music keeps playing; the silence sits underneath it.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        do {
            // One second of zero PCM (8 kHz, 16-bit mono) built in memory: no file, no mic, no dependency.
            let sampleBytes: UInt32 = 16_000
            var data = Data()
            func word<T: FixedWidthInteger>(_ value: T) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            }
            data.append(contentsOf: "RIFF".utf8); word(sampleBytes + 36)
            data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16))
            word(UInt16(1)); word(UInt16(1)); word(UInt32(8_000)); word(UInt32(16_000))
            word(UInt16(2)); word(UInt16(16)); data.append(contentsOf: "data".utf8); word(sampleBytes)
            data.append(Data(count: Int(sampleBytes)))
            let sound = try AVAudioPlayer(data: data)
            sound.numberOfLoops = -1
            guard sound.prepareToPlay(), sound.play() else { throw NSError(domain: "Standby", code: 1) }
            player = sound
        } catch {
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            throw error
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
#endif
