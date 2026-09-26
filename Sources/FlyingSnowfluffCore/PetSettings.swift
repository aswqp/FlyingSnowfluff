import Foundation

public struct PetSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = 3
    public static let minimumHeight = 176.0
    public static let maximumHeight = 320.0

    public var height: Double {
        didSet {
            height = Self.clampedHeight(height)
        }
    }
    public var isPaused: Bool
    public var crossDisplays: Bool
    public var reduceMotion: Bool
    public var launchAtLogin: Bool
    public var isMuted: Bool
    public var quietCompanionship: Bool

    public init(
        height: Double,
        isPaused: Bool,
        crossDisplays: Bool,
        reduceMotion: Bool,
        launchAtLogin: Bool,
        isMuted: Bool,
        quietCompanionship: Bool = false
    ) {
        self.height = Self.clampedHeight(height)
        self.isPaused = isPaused
        self.crossDisplays = crossDisplays
        self.reduceMotion = reduceMotion
        self.launchAtLogin = launchAtLogin
        self.isMuted = isMuted
        self.quietCompanionship = quietCompanionship
    }

    public static let `default` = PetSettings(
        height: 208,
        isPaused: false,
        crossDisplays: false,
        reduceMotion: false,
        launchAtLogin: true,
        isMuted: true,
        quietCompanionship: false
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, height, isPaused, crossDisplays, reduceMotion, launchAtLogin, isMuted,
             quietCompanionship
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            height: try values.decode(Double.self, forKey: .height),
            isPaused: try values.decode(Bool.self, forKey: .isPaused),
            crossDisplays: try values.decode(Bool.self, forKey: .crossDisplays),
            reduceMotion: try values.decode(Bool.self, forKey: .reduceMotion),
            launchAtLogin: try values.decode(Bool.self, forKey: .launchAtLogin),
            isMuted: try values.decode(Bool.self, forKey: .isMuted),
            quietCompanionship: try values.decodeIfPresent(Bool.self, forKey: .quietCompanionship) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.schemaVersion, forKey: .schemaVersion)
        try values.encode(height, forKey: .height)
        try values.encode(isPaused, forKey: .isPaused)
        try values.encode(crossDisplays, forKey: .crossDisplays)
        try values.encode(reduceMotion, forKey: .reduceMotion)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(isMuted, forKey: .isMuted)
        try values.encode(quietCompanionship, forKey: .quietCompanionship)
    }

    public mutating func clampHeight() {
        height = Self.clampedHeight(height)
    }

    private static func clampedHeight(_ height: Double) -> Double {
        min(maximumHeight, max(minimumHeight, height))
    }
}

public enum PetSettingsStore {
    private static let v3Key = "settings.v3"
    private static let v2Key = "settings.v2"
    private static let v1Key = "settings.v1"

    public static func load(from defaults: UserDefaults) -> PetSettings {
        if let data = defaults.data(forKey: v3Key),
           let settings = try? JSONDecoder().decode(PetSettings.self, from: data) {
            return settings
        }
        if let data = defaults.data(forKey: v2Key),
           let settings = try? JSONDecoder().decode(PetSettings.self, from: data) {
            save(settings, to: defaults)
            return settings
        }
        guard let data = defaults.data(forKey: v1Key),
              let legacy = try? JSONDecoder().decode(LegacyPetSettings.self, from: data)
        else { return .default }

        let migrated = PetSettings(
            height: migratedHeight(from: legacy.height),
            isPaused: legacy.isPaused,
            crossDisplays: legacy.crossDisplays,
            reduceMotion: legacy.reduceMotion,
            launchAtLogin: legacy.launchAtLogin,
            isMuted: legacy.isMuted
        )
        save(migrated, to: defaults)
        return migrated
    }

    public static func save(_ settings: PetSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: v3Key)
    }

    private static func migratedHeight(from legacyHeight: Double) -> Double {
        let tiers: [(legacy: Double, current: Double)] = [
            (112, 176),
            (160, 208),
            (208, 256),
            (256, 320)
        ]
        return tiers.dropFirst().reduce(tiers[0]) { nearest, candidate in
            abs(candidate.legacy - legacyHeight) < abs(nearest.legacy - legacyHeight) ? candidate : nearest
        }.current
    }
}

private struct LegacyPetSettings: Decodable {
    var height: Double
    var isPaused: Bool
    var crossDisplays: Bool
    var reduceMotion: Bool
    var launchAtLogin: Bool
    var isMuted: Bool
}
