import AVFAudio
import SwiftUI

@main
struct IslandDemoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    init() {
        Notices.shared.setUp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { Notices.shared.requestOnce() }
        }
        .onChange(of: scenePhase) { phase in model.scene(phase) }
    }
}

/// Ties the three pieces together: standby (silent audio) keeps the process alive, the poller brings
/// answers, and each answer feeds the island and the local notifications.
@MainActor
final class AppModel: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "server.url"); restartPoll() }
    }
    @Published var serverToken: String {
        didSet { UserDefaults.standard.set(serverToken, forKey: "server.token"); restartPoll() }
    }
    @Published var standbyEnabled: Bool {
        didSet { UserDefaults.standard.set(standbyEnabled, forKey: "standby.enabled"); updateReception() }
    }
    @Published private(set) var pollStatus = "未开始"
    @Published private(set) var standbyStatus = ""
    @Published private(set) var islandStatus = "none"
    @Published private(set) var lastLine = ""
    @Published private(set) var lastMessage = ""
    @Published private(set) var log: [String] = []

    private let standby = Standby()
    private let poller = Poller()
    private var island: IslandController!
    private var scenePhase: ScenePhase = .inactive
    private var interrupted = false

    init() {
        serverURL = UserDefaults.standard.string(forKey: "server.url") ?? ""
        serverToken = UserDefaults.standard.string(forKey: "server.token") ?? ""
        standbyEnabled = UserDefaults.standard.object(forKey: "standby.enabled") as? Bool ?? true
        island = IslandController(inputs: { [weak self] in
            guard let self else { return (false, false) }
            return (self.standbyEnabled, self.standby.isPlaying)
        }, log: { [weak self] line in self?.note(line) })
        islandStatus = island.status
        standby.onExpiration = { [weak self] in self?.updateReception() }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] notification in
            guard let self,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                self.interrupted = type == .began
                self.updateReception()
            }
        }
    }

    func scene(_ phase: ScenePhase) {
        scenePhase = phase
        note("scene \(phase)")
        standby.setScenePhase(phase)
        if phase == .active { Notices.shared.clearBadge() }
        updateReception()
        island.setScene(phase)
        islandStatus = island.status
    }

    func preview(_ state: SpriteState) {
        island.showPreview(state.rawValue)
        islandStatus = island.status
    }

    private var baseURL: URL? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private func restartPoll() {
        poller.stop()
        updateReception()
    }

    /// The one place that decides what runs: the silent audio, the poll, and the status words.
    private func updateReception() {
        if standby.state.shouldPlay(enabled: standbyEnabled, blocked: interrupted) {
            do { try standby.start() } catch { standbyStatus = "待机音频暂不可用，后台接收可能暂停" }
        } else {
            standby.stop()
        }
        let canPoll = standby.state.canPoll(lease: standby.hasLease, audio: standby.isPlaying)
        if interrupted { standbyStatus = "声音被系统占用，待机已暂停" }
        else if standby.isPlaying { standbyStatus = "后台待机已开启" }
        else if scenePhase == .background { standbyStatus = canPoll ? "短时后台接收中" : "后台接收已暂停" }
        else if !standbyEnabled { standbyStatus = "待机已关闭，只在前台接收" }
        else { standbyStatus = "前台直接接收；离开 App 时自动开启待机" }

        guard canPoll, let base = baseURL else {
            poller.stop()
            pollStatus = baseURL == nil ? "服务器地址不对" : "已暂停"
            return
        }
        guard !poller.isRunning else { return }
        pollStatus = "连接中"
        poller.token = serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        poller.start(base: base, presence: { [weak self] in
            guard let self else { return (true, false) }
            return (self.scenePhase != .active, self.standby.isPlaying)
        }, onAnswer: { [weak self] response in
            self?.answered(response)
        }, onError: { [weak self] message in
            self?.pollStatus = "出错：\(message)"
        })
    }

    private func answered(_ response: PollResponse) {
        pollStatus = "已连接 " + Self.clock.string(from: Date())
        island.serverUpdate(response.island)
        islandStatus = island.status
        if let line = response.island?.line, !line.isEmpty { lastLine = line }
        let fresh = Notices.shared.handle(messages: response.messages, foreground: scenePhase == .active)
        if let last = fresh.last { lastMessage = last.text }
    }

    private func note(_ line: String) {
        log.append(Self.clock.string(from: Date()) + " " + line)
        if log.count > 40 { log.removeFirst(log.count - 40) }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("服务器地址", text: $model.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("钥匙", text: $model.serverToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("App 会一直对 /status?wait=20 发长轮询。server/demo_server.py 就是一个最小的例子。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("后台") {
                    Toggle("离开 App 后保持待机", isOn: $model.standbyEnabled)
                    LabeledContent("待机", value: model.standbyStatus)
                    LabeledContent("轮询", value: model.pollStatus)
                }
                Section("岛") {
                    LabeledContent("状态", value: model.islandStatus)
                    LabeledContent("这一句", value: model.lastLine)
                    HStack {
                        ForEach(SpriteState.allCases, id: \.self) { state in
                            Button(state.rawValue) { model.preview(state) }.buttonStyle(.bordered)
                        }
                    }
                    Text("点一个预览，然后上滑回桌面：岛只在 App 外面显示，10 秒后恢复服务器给的状态。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("通知") {
                    LabeledContent("最近一条", value: model.lastMessage)
                    Text("App 在后台时，服务器 /say 的新消息会变成本地通知；App 打开时不弹。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("记录") {
                    ForEach(Array(model.log.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Island without push")
        }
    }
}
