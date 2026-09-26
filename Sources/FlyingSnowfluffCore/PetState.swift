import Foundation

public enum PetActivity: String, Codable, CaseIterable, Sendable {
    case ambient
    case idle
    case working
    case toolRunning
    case needsInput
    case failed
    case ready
}

public struct PetStateCoordinator: Sendable {
    private var needsInputSince: Date?
    private var failedSince: Date?
    private var readySince: Date?
    private var working: (activity: PetActivity, since: Date)?

    public init() {}

    public mutating func receive(_ activity: PetActivity, at date: Date = Date()) {
        switch activity {
        case .needsInput:
            needsInputSince = date
        case .failed:
            failedSince = date
        case .ready:
            readySince = date
            working = nil
        case .working:
            needsInputSince = nil
            failedSince = nil
            readySince = nil
            working = (.working, date)
        case .toolRunning:
            failedSince = nil
            readySince = nil
            working = (.toolRunning, date)
        case .idle, .ambient:
            needsInputSince = nil
            failedSince = nil
            readySince = nil
            working = nil
        }
    }

    public mutating func current(at date: Date = Date()) -> PetActivity {
        if needsInputSince != nil { return .needsInput }
        if let failedSince, date.timeIntervalSince(failedSince) < 10 { return .failed }
        self.failedSince = nil
        if let readySince, date.timeIntervalSince(readySince) < 8 { return .ready }
        self.readySince = nil
        if let working, date.timeIntervalSince(working.since) < 600 { return working.activity }
        self.working = nil
        return .ambient
    }
}
