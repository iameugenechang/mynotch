import AppIdentity
import AppIdentityAdapters
import XCTest

final class PreferencesMigrationTests: XCTestCase {
    final class Memory: PreferencesDomain {
        var values: [String: Any] = [:]
        var fails = false
        var dropsWrites = false
        func read() throws -> [String: Any] { values }
        func replace(with values: [String: Any]) throws {
            if fails { throw Failure.storage }
            if !dropsWrites { self.values = values }
        }
    }
    enum Failure: Error { case storage }

    func testSharedDomainContractAndMigration() throws {
        let old = "anotchup.tests.legacy.\(UUID())", new = "anotchup.tests.new.\(UUID())"
        let defaults = UserDefaults(suiteName: new)!
        defer { defaults.removePersistentDomain(forName: old); defaults.removePersistentDomain(forName: new) }
        for (source, destination) in [
            (Memory() as any PreferencesDomain, Memory() as any PreferencesDomain),
            (UserDefaultsDomain(name: old, defaults: defaults), UserDefaultsDomain(name: new, defaults: defaults))
        ] {
            XCTAssertTrue(try source.read().isEmpty)
            try source.replace(with: ["oneGoal.current": Data([0, 1, 2]), "enabled": true, "list": ["a"], "date": Date(timeIntervalSince1970: 100)])
            try destination.replace(with: ["enabled": false, "list": [String](), "newOnly": 4])
            XCTAssertTrue(try PreferencesMigration.run(source: source, destination: destination))
            let migrated = try destination.read()
            XCTAssertEqual(migrated["enabled"] as? Bool, false)
            XCTAssertEqual(migrated["list"] as? [String], [])
            XCTAssertEqual(migrated["oneGoal.current"] as? Data, Data([0, 1, 2]), "opaque feature data is preserved, not silently reset")
            XCTAssertEqual(migrated["newOnly"] as? Int, 4)
            XCTAssertNil(try source.read()[PreferencesMigration.marker])
            var edited = migrated
            edited.removeValue(forKey: "oneGoal.current")
            try destination.replace(with: edited)
            XCTAssertFalse(try PreferencesMigration.run(source: source, destination: destination))
            XCTAssertNil(try destination.read()["oneGoal.current"])
        }
    }

    func testFreshInstallAndPartialMigration() throws {
        let source = Memory(), target = Memory()
        XCTAssertTrue(try PreferencesMigration.run(source: source, destination: target))
        XCTAssertEqual(target.values.count, 1)
        target.values = ["kept": 3]
        source.values = ["kept": 1, "missing": 2]
        XCTAssertTrue(try PreferencesMigration.run(source: source, destination: target))
        XCTAssertEqual(target.values["kept"] as? Int, 3)
        XCTAssertEqual(target.values["missing"] as? Int, 2)
    }

    func testCorruptionStorageFailureAndRetry() throws {
        let source = Memory(), target = Memory()
        source.values = ["value": "source"]
        target.values = [PreferencesMigration.marker: 7]
        XCTAssertThrowsError(try PreferencesMigration.run(source: source, destination: target))
        target.values = [:]
        target.fails = true
        XCTAssertThrowsError(try PreferencesMigration.run(source: source, destination: target))
        XCTAssertTrue(target.values.isEmpty)
        target.fails = false
        target.dropsWrites = true
        XCTAssertThrowsError(try PreferencesMigration.run(source: source, destination: target))
        target.dropsWrites = false
        XCTAssertTrue(try PreferencesMigration.run(source: source, destination: target))
        XCTAssertEqual(source.values["value"] as? String, "source")
        source.values = ["invalid": NSObject()]
        target.values = [:]
        XCTAssertThrowsError(try PreferencesMigration.run(source: source, destination: target))
        XCTAssertTrue(target.values.isEmpty)
    }
}
