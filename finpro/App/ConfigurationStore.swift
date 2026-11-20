//
//  ConfigurationStore.swift
//  finpro
//
//  Keeps AppConfiguration edits from Debug Settings across launches (ZV-15). Owner: Zildjian Vito.
//

import Foundation

nonisolated struct ConfigurationStore: @unchecked Sendable {
    static let key = "AppConfiguration"
    static let versionKey = "AppConfiguration.version"
    /// Bump when a default changes in a way saved settings must pick up, and add the step to `migrate`.
    /// 1 (2026-11-04): first finpro version. PoC settings (versions 2–3) are not carried over:
    /// the new bundle ID starts with empty UserDefaults.
    /// 2 (2026-11-20): pre-roll 2 → 3 s and countdown 3 → 0 s (the pre-roll replaced the countdown).
    /// 3 (2026-11-20): pass threshold 0.75 → 0.30 and missed-note threshold 0.50 → 0.30.
    static let currentVersion = 3

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Saved configuration, or the defaults when nothing is saved or the saved data no longer decodes.
    func load() -> AppConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              var configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        let version = defaults.integer(forKey: Self.versionKey)
        if version < Self.currentVersion {
            configuration = Self.migrate(configuration, from: version)
            save(configuration)
        }
        return configuration
    }

    /// Brings settings saved by an older version up to new defaults. Values the user changed
    /// themselves are kept.
    static func migrate(_ old: AppConfiguration, from version: Int) -> AppConfiguration {
        var configuration = old
        if version < 2 {
            if configuration.preRoll == 2.0 { configuration.preRoll = AppConfiguration.default.preRoll }
            if configuration.countdownSeconds == 3 { configuration.countdownSeconds = AppConfiguration.default.countdownSeconds }
        }
        if version < 3 {
            if configuration.passThreshold == 0.75 { configuration.passThreshold = AppConfiguration.default.passThreshold }
            if configuration.missedNoteThreshold == 0.50 { configuration.missedNoteThreshold = AppConfiguration.default.missedNoteThreshold }
        }
        return configuration
    }

    func save(_ configuration: AppConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.key)
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
