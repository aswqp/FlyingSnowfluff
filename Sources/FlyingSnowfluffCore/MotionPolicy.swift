import Foundation

public enum IdleMicroCue: Sendable { case rest, smile, blink, front, lookLeft, lookRight }

public enum IdleMicroMotion {
    /// Short accents separated by long rests; no bubble, movement or event state.
    public static func cue(elapsed: Double) -> IdleMicroCue {
        guard elapsed.isFinite, elapsed >= 0 else { return .rest }
        let phase=elapsed.truncatingRemainder(dividingBy:44)
        let alternate=elapsed.truncatingRemainder(dividingBy:88)<44
        if (10...10.9).contains(phase) { return .smile }
        if (12.2...12.35).contains(phase) || (12.5...12.65).contains(phase) { return .blink }
        if (24...24.15).contains(phase) || (24.7...24.85).contains(phase) || (36...36.15).contains(phase) || (36.7...36.85).contains(phase) { return .front }
        if (24.15...24.7).contains(phase) { return alternate ? .lookLeft : .lookRight }
        if (36.15...36.7).contains(phase) { return alternate ? .lookRight : .lookLeft }
        return .rest
    }
}

public enum PetGesture: String, Codable, CaseIterable, Sendable {
    case wave
    case shy
    case tilt
    case adjustVisor
    case nap
    case sway
    case peek
}

public struct GesturePicker: Sendable {
    private var random: SeededRandom
    private var recent: [PetGesture] = []

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
    }

    public mutating func next(from candidates: [PetGesture]) -> PetGesture? {
        let unique = candidates.reduce(into: [PetGesture]()) { result, gesture in
            if !result.contains(gesture) { result.append(gesture) }
        }
        guard !unique.isEmpty else { return nil }

        let available = unique.filter { !recent.contains($0) }
        let pool: [PetGesture]
        if !available.isEmpty {
            pool = available
        } else {
            let leastRecent = unique.min { lhs, rhs in
                recency(of: lhs) < recency(of: rhs)
            }
            pool = leastRecent.map { [$0] } ?? unique
        }

        let index = min(pool.count - 1, Int(random.nextUnit() * Double(pool.count)))
        let selected = pool[index]
        recent.removeAll { $0 == selected }
        recent.append(selected)
        if recent.count > 2 { recent.removeFirst(recent.count - 2) }
        return selected
    }

    private func recency(of gesture: PetGesture) -> Int {
        recent.lastIndex(of: gesture) ?? -1
    }
}

public enum MotionPolicy {
    public static func allowsAutomaticFlight(
        activity: PetActivity,
        paused: Bool,
        hidden: Bool,
        hovering: Bool,
        quiet: Bool,
        reduceMotion: Bool
    ) -> Bool {
        allowsAutomaticAction(
            activity: activity,
            paused: paused,
            hidden: hidden,
            hovering: hovering,
            quiet: quiet,
            reduceMotion: reduceMotion
        )
    }

    public static func allowsAmbientGesture(
        activity: PetActivity,
        paused: Bool,
        hidden: Bool,
        hovering: Bool,
        quiet: Bool,
        reduceMotion: Bool
    ) -> Bool {
        allowsAutomaticAction(
            activity: activity,
            paused: paused,
            hidden: hidden,
            hovering: hovering,
            quiet: quiet,
            reduceMotion: reduceMotion
        )
    }

    private static func allowsAutomaticAction(
        activity: PetActivity,
        paused: Bool,
        hidden: Bool,
        hovering: Bool,
        quiet: Bool,
        reduceMotion: Bool
    ) -> Bool {
        guard activity == .ambient || activity == .idle else { return false }
        return !paused && !hidden && !hovering && !quiet && !reduceMotion
    }
}

public struct BubbleCooldown: Sendable {
    public let interval: TimeInterval
    private var lastAllowed: TimeInterval?

    public init(interval: TimeInterval = 300) {
        self.interval = max(0, interval.isFinite ? interval : 300)
    }

    public mutating func allow(now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        guard let lastAllowed else {
            self.lastAllowed = now
            return true
        }
        if now < lastAllowed || now - lastAllowed >= interval {
            self.lastAllowed = now
            return true
        }
        return false
    }
}

public enum FlightPhase: String, Codable, CaseIterable, Sendable {
    case preparing
    case cruising
    case settling
}

public enum FlightMotion {
    public static func phase(progress: Double) -> FlightPhase {
        let bounded = progress.isFinite ? min(1, max(0, progress)) : 0
        if bounded < 0.12 { return .preparing }
        if bounded < 0.82 { return .cruising }
        return .settling
    }

    public static func preferredFramesPerSecond(lowPower: Bool) -> Int {
        lowPower ? 30 : 60
    }

    public static func quantizedBankAngle(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        let clamped = min(0.05, max(-0.05, radians))
        return (clamped / 0.005).rounded() * 0.005
    }

    public static func springOffset(elapsed: TimeInterval) -> Point2D {
        guard elapsed.isFinite, elapsed > 0, elapsed < 1 else {
            return Point2D(x: 0, y: 0)
        }
        let envelope = sin(.pi * elapsed)
        let oscillation = sin(6 * .pi * elapsed)
        let value = min(4, max(-4, 4 * envelope * oscillation))
        return Point2D(x: value * 0.35, y: value)
    }
}
