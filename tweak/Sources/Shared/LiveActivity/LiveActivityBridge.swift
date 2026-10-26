// ActivityKit is Swift only, so LiveActivity.x reaches it through this class.
import ActivityKit
import Foundation
import os

@available(iOS 17.0, *)
@objc(SGLiveActivityBridge)
public final class SGLiveActivityBridge: NSObject {
    private static let log = Logger(subsystem: "spotifyglass", category: "live activity")

    private static var lyricsActivityID: String?
    private static var songActivityID: String?

    private static var lyricsActivity: Activity<SGLyricsAttributes>? {
        let activities = Activity<SGLyricsAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let id = lyricsActivityID, let found = activities.first(where: { $0.id == id }) {
            return found
        }
        return activities.first { $0.content.state.view == .lyrics }
    }

    private static var songActivity: Activity<SGLyricsAttributes>? {
        let activities = Activity<SGLyricsAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let id = songActivityID, let found = activities.first(where: { $0.id == id }) {
            return found
        }
        return activities.first { $0.content.state.view == .panel || $0.content.state.view == .queue }
    }

    @objc public static var isShowing: Bool {
        !Activity<SGLyricsAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.isEmpty
    }

    private enum Change: Sendable {
        case update(String, ActivityContent<SGLyricsAttributes.ContentState>)
        case end([String])
    }

    private struct Pending: Sendable {
        var changes: [Change] = []
        var sending = false
    }

    private static let pending = OSAllocatedUnfairLock(initialState: Pending())

    private static func queue(_ change: Change) {
        let start = pending.withLock { pending in
            if case .update(let id, _) = change, case .update(let waiting, _)? = pending.changes.last, waiting == id {
                pending.changes.removeLast()
            }
            pending.changes.append(change)
            if pending.sending { return false }
            pending.sending = true
            return true
        }
        if start { Task { await send() } }
    }

    private static func send() async {
        while let change = pending.withLock({ pending -> Change? in
            if pending.changes.isEmpty {
                pending.sending = false
                return nil
            }
            return pending.changes.removeFirst()
        }) {
            let activities = Activity<SGLyricsAttributes>.activities
            switch change {
            case .update(let id, let content):
                await activities.first { $0.id == id }?.update(content)
            case .end(let ids):
                for activity in activities where ids.contains(activity.id) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    @objc public static func showLyrics(paused: Bool, line: String, nextLine: String) {
        let state = SGLyricsAttributes.ContentState(
            view: .lyrics, paused: paused, line: line, nextLine: nextLine,
            tracks: [], tab: .controls, title: "", artist: "",
            shuffle: false, repeatMode: 0, timerEnd: nil, timerEndOfTrack: false)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = lyricsActivity {
            lyricsActivityID = activity.id
            queue(.update(activity.id, content))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("[spotifyglass] live activity: activities are off for this app")
            return
        }
        do {
            let activity = try Activity.request(attributes: SGLyricsAttributes(), content: content, pushType: nil)
            lyricsActivityID = activity.id
            log.notice("[spotifyglass] live activity: started lyrics \(activity.id, privacy: .public)")
        } catch {
            log.error("[spotifyglass] live activity: lyrics request failed: \(String(describing: error), privacy: .public)")
        }
    }

    @objc public static func showSong(paused: Bool,
                                      titles: [String], artists: [String], uris: [String],
                                      tab: Int, title: String, artist: String, shuffle: Bool, repeatMode: Int,
                                      timerEnd: Date?, timerEndOfTrack: Bool) {
        let tracks = titles.indices.map {
            SGLyricsAttributes.Track(title: titles[$0], artist: artists[$0], uri: uris[$0])
        }
        let state = SGLyricsAttributes.ContentState(
            view: .panel, paused: paused, line: "", nextLine: "",
            tracks: tracks, tab: SGLyricsAttributes.Tab(rawValue: tab) ?? .controls,
            title: title, artist: artist, shuffle: shuffle, repeatMode: repeatMode,
            timerEnd: timerEnd, timerEndOfTrack: timerEndOfTrack)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = songActivity {
            songActivityID = activity.id
            queue(.update(activity.id, content))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("[spotifyglass] live activity: activities are off for this app")
            return
        }
        do {
            let activity = try Activity.request(attributes: SGLyricsAttributes(), content: content, pushType: nil)
            songActivityID = activity.id
            log.notice("[spotifyglass] live activity: started song \(activity.id, privacy: .public)")
        } catch {
            log.error("[spotifyglass] live activity: song request failed: \(String(describing: error), privacy: .public)")
        }
    }

    @objc public static func show(view: Int, paused: Bool, line: String, nextLine: String,
                                  titles: [String], artists: [String], uris: [String],
                                  tab: Int, title: String, artist: String, shuffle: Bool, repeatMode: Int,
                                  timerEnd: Date?, timerEndOfTrack: Bool) {
        if view == SGLyricsAttributes.View.lyrics.rawValue {
            showLyrics(paused: paused, line: line, nextLine: nextLine)
        } else {
            showSong(paused: paused, titles: titles, artists: artists, uris: uris,
                     tab: tab, title: title, artist: artist, shuffle: shuffle, repeatMode: repeatMode,
                     timerEnd: timerEnd, timerEndOfTrack: timerEndOfTrack)
        }
    }

    // Named now, so an activity requested after this call is not ended with them.
    @objc public static func end() {
        lyricsActivityID = nil
        songActivityID = nil
        queue(.end(Activity<SGLyricsAttributes>.activities.map(\.id)))
    }
}
