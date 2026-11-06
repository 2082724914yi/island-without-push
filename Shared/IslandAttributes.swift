#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The one Live Activity. No images ride in here (without App Groups the extension cannot read the
/// App's files): only a sprite name and one short line, far below ActivityKit's 4 KB limit. The sprite
/// itself is compiled into both targets from Shared/PixelArt.swift.
@available(iOS 16.1, *)
struct IslandAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// One of SpriteState's names, as the server gave it.
        var state: String
        /// The line of the moment (≤ 30 characters).
        var line: String
    }
}

enum IslandWords {
    /// Shown by the extension once the activity passed its staleDate: the App stopped answering.
    static let stale = "后台掉了，点开 App 看看"
}
#endif
