import Foundation
import Testing
@testable import FlyingSnowfluffCore

@Suite("Pet settings")
struct PetSettingsTests {
    @Test func defaultsMatchProductContract() {
        let settings = PetSettings.default
        #expect(settings.height == 208)
        #expect(!settings.isPaused)
        #expect(!settings.crossDisplays)
        #expect(!settings.reduceMotion)
        #expect(settings.launchAtLogin)
        #expect(settings.isMuted)
        #expect(!settings.quietCompanionship)
    }

    @Test func decodeClampsUnsafePetHeight() throws {
        let tooSmall = Data(#"{"height":12,"isPaused":false,"crossDisplays":true,"reduceMotion":false,"launchAtLogin":true,"isMuted":true}"#.utf8)
        let settings = try JSONDecoder().decode(PetSettings.self, from: tooSmall)
        #expect(settings.height == 176)

        let tooLarge = Data(#"{"height":900,"isPaused":false,"crossDisplays":true,"reduceMotion":false,"launchAtLogin":true,"isMuted":true}"#.utf8)
        let large = try JSONDecoder().decode(PetSettings.self, from: tooLarge)
        #expect(large.height == 320)
    }

    @Test func assignedHeightIsClampedToV2Range() {
        var settings = PetSettings.default
        settings.height = 12
        #expect(settings.height == 176)

        settings.height = 900
        #expect(settings.height == 320)
    }

    @Test func settingsRoundTrip() throws {
        var settings = PetSettings.default
        settings.height = 256
        settings.crossDisplays = true
        settings.reduceMotion = true
        settings.quietCompanionship = true
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(PetSettings.self, from: encoded) == settings)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 3)
        #expect(json["quietCompanionship"] as? Bool == true)
    }

    @Test func storePrefersV3OverV2AndV1() throws {
        try withIsolatedDefaults { defaults in
            let v2 = PetSettings(
                height: 256,
                isPaused: true,
                crossDisplays: true,
                reduceMotion: true,
                launchAtLogin: false,
                isMuted: false
            )
            PetSettingsStore.save(v2, to: defaults)
            let savedV3 = try #require(defaults.data(forKey: "settings.v3"))
            defaults.set(legacyData(height: 112), forKey: "settings.v2")
            defaults.set(legacyData(height: 112), forKey: "settings.v1")

            #expect(PetSettingsStore.load(from: defaults) == v2)
            #expect(defaults.data(forKey: "settings.v3") == savedV3)
        }
    }

    @Test func storeMigratesNearestV1HeightAndPreservesPreferences() throws {
        try withIsolatedDefaults { defaults in
            let legacy = legacyData(
                height: 181,
                isPaused: true,
                crossDisplays: true,
                reduceMotion: true,
                launchAtLogin: false,
                isMuted: false
            )
            defaults.set(legacy, forKey: "settings.v1")

            let migrated = PetSettingsStore.load(from: defaults)

            #expect(migrated.height == 208)
            #expect(migrated.isPaused)
            #expect(migrated.crossDisplays)
            #expect(migrated.reduceMotion)
            #expect(!migrated.launchAtLogin)
            #expect(!migrated.isMuted)
            #expect(defaults.data(forKey: "settings.v1") == legacy)
            let v3Data = try #require(defaults.data(forKey: "settings.v3"))
            #expect(try JSONDecoder().decode(PetSettings.self, from: v3Data) == migrated)
            #expect(!migrated.quietCompanionship)
        }
    }

    @Test func storeLoadsV2WithoutNewKeyAndWritesV3() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(legacyData(
                height: 256,
                isPaused: true,
                crossDisplays: true,
                reduceMotion: true,
                launchAtLogin: false,
                isMuted: false
            ), forKey: "settings.v2")

            let migrated = PetSettingsStore.load(from: defaults)

            #expect(migrated.height == 256)
            #expect(migrated.isPaused)
            #expect(migrated.crossDisplays)
            #expect(migrated.reduceMotion)
            #expect(!migrated.launchAtLogin)
            #expect(!migrated.isMuted)
            #expect(!migrated.quietCompanionship)
            #expect(defaults.data(forKey: "settings.v3") != nil)
        }
    }

    @Test func storeFallsBackToDefaultWhenNoSettingsExist() throws {
        try withIsolatedDefaults { defaults in
            #expect(PetSettingsStore.load(from: defaults) == .default)
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "FlyingSnowfluffCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func legacyData(
        height: Double,
        isPaused: Bool = false,
        crossDisplays: Bool = false,
        reduceMotion: Bool = false,
        launchAtLogin: Bool = true,
        isMuted: Bool = true
    ) -> Data {
        Data("""
        {"height":\(height),"isPaused":\(isPaused),"crossDisplays":\(crossDisplays),"reduceMotion":\(reduceMotion),"launchAtLogin":\(launchAtLogin),"isMuted":\(isMuted)}
        """.utf8)
    }
}
