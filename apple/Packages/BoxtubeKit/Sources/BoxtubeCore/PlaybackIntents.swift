import Foundation
import AppIntents

/// Buttons on the Live Activity run these in the app's process.
public enum PlaybackCommand: String, Sendable { case toggle, back, forward }

@MainActor
public enum PlaybackIntentBridge {
    public static var handler: ((PlaybackCommand) -> Void)?
}

#if os(iOS)
public struct TogglePlaybackIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Play or pause"
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.handler?(.toggle)
        return .result()
    }
}

public struct SkipBackIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Back 10 seconds"
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.handler?(.back)
        return .result()
    }
}

public struct SkipForwardIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Forward 10 seconds"
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        PlaybackIntentBridge.handler?(.forward)
        return .result()
    }
}
#endif
