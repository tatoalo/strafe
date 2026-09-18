import Foundation

enum Preferences {
    static let domain = "com.tatoalo.strafe"
    static let legacyDomain = "com.rileycx.strafe"

    nonisolated(unsafe) static let store: UserDefaults = {
        let destination = Bundle.main.bundleIdentifier == domain
            ? UserDefaults.standard : UserDefaults(suiteName: domain)!
        migrateLegacyPreferences(
            UserDefaults.standard.persistentDomain(forName: legacyDomain) ?? [:],
            into: destination
        )
        return destination
    }()

    static func migrateLegacyPreferences(_ legacy: [String: Any], into destination: UserDefaults) {
        guard !destination.bool(forKey: "legacyPreferencesMigrated") else { return }
        for key in ["transitionSpeed", "spaceHotkeysEnabled"] {
            if destination.object(forKey: key) == nil, let value = legacy[key] {
                destination.set(value, forKey: key)
            }
        }
        destination.set(true, forKey: "legacyPreferencesMigrated")
    }
}
