import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandBundle: WidgetBundle {
    var body: some Widget {
        IslandLiveActivity()
    }
}

/// The Dynamic Island and the lock-screen banner. Everything shown comes from the ContentState the
/// App sends (a sprite name and a line); the sprites are compiled in from Shared/PixelArt.swift.
struct IslandLiveActivity: Widget {
    /// The compact island shows the compact grid at 1 pt per art pixel.
    static let compactScale: CGFloat = 1
    /// Expanded island and lock screen: the wide grid at 2 pt per art pixel.
    static let wideScale: CGFloat = 2
    /// The minimal island (another app's activity sits beside ours, so each gets a small circle)
    /// shows a window around the sprite's middle.
    static let minimalCrop = PixelCrop(x: 4, y: 3, w: 20, h: 18)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { context in
            LockScreenBanner(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.78))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            let sprite = SpriteState(name: state.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    SpriteView(state: sprite, wide: true, scale: IslandLiveActivity.wideScale, gray: stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(stale ? IslandWords.stale : state.line)
                        .font(.subheadline).lineLimit(1)
                        .foregroundStyle(stale ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                SpriteView(state: sprite, scale: IslandLiveActivity.compactScale, gray: stale).padding(.leading, 2)
            } compactTrailing: {
                Circle()
                    .fill(stale ? Color.gray : SpriteState.onlineGreen)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 4)
            } minimal: {
                SpriteView(state: sprite, scale: 1, gray: stale, crop: IslandLiveActivity.minimalCrop)
            }
        }
    }
}

struct LockScreenBanner: View {
    let state: IslandAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(spacing: 8) {
            SpriteView(state: SpriteState(name: state.state), wide: true, scale: IslandLiveActivity.wideScale, gray: stale)
            Text(stale ? IslandWords.stale : state.line)
                .font(.subheadline).lineLimit(1)
                .foregroundStyle(stale ? Color.white.opacity(0.6) : Color.white)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }
}
