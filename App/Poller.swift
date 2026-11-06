import Foundation

/// One held request at a time against `GET <base>/status?wait=20`. The server answers at once when
/// something changed and otherwise after `wait` seconds; either way the next request follows, with at
/// most one request every 2 s. Headers tell the server whether the App is in the background and
/// whether standby audio is playing (useful for the server's own "is the phone reachable" view).
@MainActor
final class Poller {
    static let wait = 20

    typealias Presence = () -> (background: Bool, standby: Bool)

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }
    var token = ""

    func start(base: URL, presence: @escaping Presence, onAnswer: @escaping (PollResponse) -> Void,
               onError: @escaping (String) -> Void) {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let started = Date()
                do {
                    let response = try await self.fetch(base: base, presence: presence())
                    guard !Task.isCancelled else { break }
                    onAnswer(response)
                } catch is CancellationError {
                    break
                } catch {
                    if !Task.isCancelled { onError(error.localizedDescription) }
                }
                let pause = 2 - Date().timeIntervalSince(started)
                if pause > 0 { try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func fetch(base: URL, presence: (background: Bool, standby: Bool)) async throws -> PollResponse {
        var components = URLComponents(url: base.appendingPathComponent("status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "wait", value: String(Self.wait))]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = TimeInterval(Self.wait + 15)
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue(presence.background ? "background" : "foreground", forHTTPHeaderField: "X-Presence")
        request.setValue(presence.standby ? "on" : "off", forHTTPHeaderField: "X-Standby")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PollError("没有回应") }
        guard (200..<300).contains(http.statusCode) else { throw PollError("HTTP \(http.statusCode)") }
        do { return try JSONDecoder().decode(PollResponse.self, from: data) }
        catch { throw PollError("回应不是预期的 JSON") }
    }
}

struct PollError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
