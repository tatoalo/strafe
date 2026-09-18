import Foundation
import XCTest
@testable import strafe

final class PreferencesTests: XCTestCase {
    func testMigrationPreservesForkChoicesAndRunsOnce() {
        let domain = "com.tatoalo.strafe.tests.\(UUID().uuidString)"
        let destination = UserDefaults(suiteName: domain)!
        defer { destination.removePersistentDomain(forName: domain) }
        destination.set(1, forKey: "transitionSpeed")
        Preferences.migrateLegacyPreferences([
            "transitionSpeed": 2, "spaceHotkeysEnabled": false,
            "SUFeedURL": "https://unexpected.example/feed.xml"
        ], into: destination)
        XCTAssertEqual(destination.integer(forKey: "transitionSpeed"), 1)
        XCTAssertEqual(destination.object(forKey: "spaceHotkeysEnabled") as? Bool, false)
        XCTAssertNil(destination.object(forKey: "SUFeedURL"))
        Preferences.migrateLegacyPreferences(["spaceHotkeysEnabled": true], into: destination)
        XCTAssertFalse(destination.bool(forKey: "spaceHotkeysEnabled"))
    }

    func testFreshMigrationCopiesSupportedPreferences() {
        let domain = "com.tatoalo.strafe.tests.\(UUID().uuidString)"
        let destination = UserDefaults(suiteName: domain)!
        defer { destination.removePersistentDomain(forName: domain) }
        Preferences.migrateLegacyPreferences(["transitionSpeed": 2], into: destination)
        XCTAssertEqual(destination.integer(forKey: "transitionSpeed"), 2)
        XCTAssertNil(destination.object(forKey: "spaceHotkeysEnabled"))
        XCTAssertTrue(destination.bool(forKey: "legacyPreferencesMigrated"))
    }
}
