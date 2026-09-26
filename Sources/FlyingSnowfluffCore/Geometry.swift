import Foundation

public struct Point2D: Codable, Equatable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point2D) -> Double {
        hypot(other.x - x, other.y - y)
    }

    public var description: String { "(\(x), \(y))" }
}

public struct Rect2D: Codable, Equatable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { min(x, x + width) }
    public var maxX: Double { max(x, x + width) }
    public var minY: Double { min(y, y + height) }
    public var maxY: Double { max(y, y + height) }

    public func insetBy(dx: Double, dy: Double) -> Rect2D {
        let clampedX = min(max(0, dx), abs(width) / 2)
        let clampedY = min(max(0, dy), abs(height) / 2)
        return Rect2D(
            x: minX + clampedX,
            y: minY + clampedY,
            width: max(0, abs(width) - clampedX * 2),
            height: max(0, abs(height) - clampedY * 2)
        )
    }

    public func contains(_ point: Point2D) -> Bool {
        point.x >= minX - 0.000_001 && point.x <= maxX + 0.000_001
            && point.y >= minY - 0.000_001 && point.y <= maxY + 0.000_001
    }

    public func formsSolidBoundingUnion(with other: Rect2D) -> Bool {
        guard width != 0, height != 0, other.width != 0, other.height != 0 else { return false }
        let overlapWidth = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let overlapHeight = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        let coveredArea = abs(width * height) + abs(other.width * other.height) - overlapWidth * overlapHeight
        let unionWidth = max(maxX, other.maxX) - min(minX, other.minX)
        let unionHeight = max(maxY, other.maxY) - min(minY, other.minY)
        let boundingArea = unionWidth * unionHeight
        let tolerance = max(1, boundingArea) * 0.000_000_001
        return abs(coveredArea - boundingArea) <= tolerance
    }

    public var description: String { "[\(minX), \(minY), \(maxX), \(maxY)]" }

    public func pixelAligned(backingScale: Double) -> Rect2D {
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let alignedMinX = (minX * scale).rounded() / scale
        let alignedMaxX = (maxX * scale).rounded() / scale
        let alignedMinY = (minY * scale).rounded() / scale
        let alignedMaxY = (maxY * scale).rounded() / scale
        return Rect2D(
            x: min(alignedMinX, alignedMaxX),
            y: min(alignedMinY, alignedMaxY),
            width: max(0, alignedMaxX - alignedMinX),
            height: max(0, alignedMaxY - alignedMinY)
        )
    }
}

public struct CubicBezierPath: Codable, Equatable, Sendable {
    public var start: Point2D
    public var control1: Point2D
    public var control2: Point2D
    public var end: Point2D

    public init(start: Point2D, control1: Point2D, control2: Point2D, end: Point2D) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    public func point(at rawT: Double) -> Point2D {
        let t = min(1, max(0, rawT))
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return Point2D(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}

public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func nextUnit() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) / Double(1 << 53)
    }

    public mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }
}

public struct FlightPlanner: Sendable {
    private var random: SeededRandom

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        random = SeededRandom(seed: seed)
    }

    public mutating func makePath(in frame: Rect2D, marginX: Double, marginY: Double) -> CubicBezierPath {
        let safe = frame.insetBy(dx: marginX, dy: marginY)
        let start = randomPoint(in: safe)
        let minimumTravel = min(320, max(80, hypot(safe.width, safe.height) * 0.28))
        var end = randomPoint(in: safe)
        for _ in 0..<24 {
            if start.distance(to: end) >= minimumTravel { break }
            end = randomPoint(in: safe)
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let arc = random.value(in: -0.32...0.32)
        let c1Base = Point2D(x: start.x + dx * 0.28, y: start.y + dy * 0.28)
        let c2Base = Point2D(x: start.x + dx * 0.72, y: start.y + dy * 0.72)
        let control1 = clamped(
            Point2D(x: c1Base.x - dy * arc, y: c1Base.y + dx * arc),
            to: safe
        )
        let control2 = clamped(
            Point2D(x: c2Base.x - dy * arc, y: c2Base.y + dx * arc),
            to: safe
        )
        return CubicBezierPath(start: start, control1: control1, control2: control2, end: end)
    }

    private mutating func randomPoint(in rect: Rect2D) -> Point2D {
        Point2D(
            x: random.value(in: rect.minX...rect.maxX),
            y: random.value(in: rect.minY...rect.maxY)
        )
    }

    private func clamped(_ point: Point2D, to rect: Rect2D) -> Point2D {
        Point2D(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }
}
