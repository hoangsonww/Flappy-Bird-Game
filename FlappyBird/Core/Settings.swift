import Foundation

/// Player preferences, backed by `UserDefaults`.
///
/// Every property is a computed accessor so a change is persisted immediately —
/// there is no "save" step to forget, and the app can be killed at any time.
final class Settings {
    static let shared = Settings(defaults: .standard)

    private enum Key {
        static let sound = "settings.sound"
        static let music = "settings.music"
        static let haptics = "settings.haptics"
        static let ghost = "settings.ghost"
        static let highContrast = "settings.highContrast"
        static let reduceFlashing = "settings.reduceFlashing"
        static let showFPS = "settings.showFPS"
        static let skin = "settings.skin"
        static let mode = "settings.mode"
        static let backendURL = "settings.backendURL"
        static let onlineEnabled = "settings.onlineEnabled"
        static let hasSeenTutorial = "settings.hasSeenTutorial"
        static let deviceId = "settings.deviceId"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Sound, haptics and the ghost default to on; everything else to off.
        defaults.register(defaults: [
            Key.sound: true,
            Key.music: true,
            Key.haptics: true,
            Key.ghost: true,
            Key.onlineEnabled: true,
            Key.highContrast: false,
            Key.reduceFlashing: false,
            Key.showFPS: false,
        ])
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.sound) }
        set { defaults.set(newValue, forKey: Key.sound) }
    }

    var musicEnabled: Bool {
        get { defaults.bool(forKey: Key.music) }
        set { defaults.set(newValue, forKey: Key.music) }
    }

    var hapticsEnabled: Bool {
        get { defaults.bool(forKey: Key.haptics) }
        set { defaults.set(newValue, forKey: Key.haptics) }
    }

    /// Show a translucent replay of the player's best run.
    var ghostEnabled: Bool {
        get { defaults.bool(forKey: Key.ghost) }
        set { defaults.set(newValue, forKey: Key.ghost) }
    }

    var highContrast: Bool {
        get { defaults.bool(forKey: Key.highContrast) }
        set { defaults.set(newValue, forKey: Key.highContrast) }
    }

    /// Suppress the red death flash and other rapid full-screen changes.
    var reduceFlashing: Bool {
        get { defaults.bool(forKey: Key.reduceFlashing) }
        set { defaults.set(newValue, forKey: Key.reduceFlashing) }
    }

    var showFPS: Bool {
        get { defaults.bool(forKey: Key.showFPS) }
        set { defaults.set(newValue, forKey: Key.showFPS) }
    }

    var selectedSkin: BirdSkin {
        get { BirdSkin(rawValue: defaults.string(forKey: Key.skin) ?? "") ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: Key.skin) }
    }

    var selectedMode: GameMode {
        get { GameMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// Explicit backend base URL. When set, discovery uses it first.
    var backendURLOverride: String? {
        get {
            let value = defaults.string(forKey: Key.backendURL)?.trimmingCharacters(in: .whitespaces)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set { defaults.set(newValue, forKey: Key.backendURL) }
    }

    /// Master switch: when off the game never touches the network.
    var onlineEnabled: Bool {
        get { defaults.bool(forKey: Key.onlineEnabled) }
        set { defaults.set(newValue, forKey: Key.onlineEnabled) }
    }

    var hasSeenTutorial: Bool {
        get { defaults.bool(forKey: Key.hasSeenTutorial) }
        set { defaults.set(newValue, forKey: Key.hasSeenTutorial) }
    }

    /// Stable per-install identifier used for guest accounts.
    var deviceId: String {
        if let existing = defaults.string(forKey: Key.deviceId), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Key.deviceId)
        return generated
    }

    /// Test helper: wipe every key this type owns.
    func resetAll() {
        for key in [
            Key.sound, Key.music, Key.haptics, Key.ghost, Key.highContrast,
            Key.reduceFlashing, Key.showFPS, Key.skin, Key.mode, Key.backendURL,
            Key.onlineEnabled, Key.hasSeenTutorial, Key.deviceId,
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
