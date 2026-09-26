import Foundation
import Testing
@testable import FlyingSnowfluffCore

@Suite("Pet state coordinator")
struct PetStateCoordinatorTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func priorityIsNeedsInputThenFailedReadyWorkingAmbient() {
        var state = PetStateCoordinator()
        state.receive(.working, at: start)
        state.receive(.ready, at: start.addingTimeInterval(1))
        state.receive(.failed, at: start.addingTimeInterval(2))
        state.receive(.needsInput, at: start.addingTimeInterval(3))

        #expect(state.current(at: start.addingTimeInterval(4)) == .needsInput)
    }

    @Test func needsInputPersistsUntilNextPromptSubmission() {
        var state = PetStateCoordinator()
        state.receive(.needsInput, at: start)
        #expect(state.current(at: start.addingTimeInterval(3_600)) == .needsInput)

        state.receive(.working, at: start.addingTimeInterval(3_601))
        #expect(state.current(at: start.addingTimeInterval(3_602)) == .working)
    }

    @Test func failureExpiresAfterTenSeconds() {
        var state = PetStateCoordinator()
        state.receive(.working, at: start)
        state.receive(.failed, at: start.addingTimeInterval(1))

        #expect(state.current(at: start.addingTimeInterval(10.9)) == .failed)
        #expect(state.current(at: start.addingTimeInterval(11.1)) == .working)
    }

    @Test func readyExpiresAfterEightSeconds() {
        var state = PetStateCoordinator()
        state.receive(.ready, at: start)
        #expect(state.current(at: start.addingTimeInterval(7.9)) == .ready)
        #expect(state.current(at: start.addingTimeInterval(8.1)) == .ambient)
    }

    @Test func staleWorkingFallsBackAfterTenMinutes() {
        var state = PetStateCoordinator()
        state.receive(.working, at: start)
        #expect(state.current(at: start.addingTimeInterval(599)) == .working)
        #expect(state.current(at: start.addingTimeInterval(601)) == .ambient)
    }

    @Test func sessionEndClearsTransientState() {
        var state = PetStateCoordinator()
        state.receive(.needsInput, at: start)
        state.receive(.idle, at: start.addingTimeInterval(1))
        #expect(state.current(at: start.addingTimeInterval(2)) == .ambient)
    }
}
