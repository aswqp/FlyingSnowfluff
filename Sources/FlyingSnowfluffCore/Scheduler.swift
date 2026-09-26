import Foundation

public struct ActionScheduler: Sendable {
    private var random: SeededRandom

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
    }

    public mutating func nextFlightDelay(reduceMotion: Bool) -> TimeInterval {
        random.value(in: reduceMotion ? 240...480 : 120...300)
    }

    public mutating func nextFlightDuration(reduceMotion: Bool) -> TimeInterval {
        random.value(in: reduceMotion ? 7...12 : 4...9)
    }

    public mutating func nextAmbientDelay() -> TimeInterval {
        random.value(in: 60...150)
    }
}
