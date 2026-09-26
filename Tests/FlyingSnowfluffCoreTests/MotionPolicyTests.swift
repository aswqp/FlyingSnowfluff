import Foundation
import Testing
@testable import FlyingSnowfluffCore

@Suite("Motion policy")
struct MotionPolicyTests {
    @Test func idleMicroCuesAreBriefAndReturnToRest() {
        #expect(IdleMicroMotion.cue(elapsed:0) == .rest)
        #expect(IdleMicroMotion.cue(elapsed:10.3) == .smile)
        #expect(IdleMicroMotion.cue(elapsed:12.25) == .blink)
        #expect(IdleMicroMotion.cue(elapsed:12.55) == .blink)
        #expect(IdleMicroMotion.cue(elapsed:24.3) == .lookLeft)
        #expect(IdleMicroMotion.cue(elapsed:36.3) == .lookRight)
        #expect(IdleMicroMotion.cue(elapsed:38) == .rest)
        #expect(IdleMicroMotion.cue(elapsed:Double.nan) == .rest)
        #expect(IdleMicroMotion.cue(elapsed:68.3) == .lookRight)
    }
    @Test func gesturePickerAvoidsItsRecentTwoSelections() {
        var picker = GesturePicker(seed: 0x51A7)
        let choices = PetGesture.allCases
        var selected: [PetGesture] = []
        for _ in 0..<100 {
            let gesture = picker.next(from: choices)
            #expect(gesture != nil)
            if let gesture {
                #expect(!selected.suffix(2).contains(gesture))
                selected.append(gesture)
            }
        }
    }

    @Test func gesturePickerHandlesEmptySingletonAndPairPools() {
        var picker = GesturePicker(seed: 7)
        #expect(picker.next(from: []) == nil)
        #expect(picker.next(from: [.wave]) == .wave)
        #expect(picker.next(from: [.wave]) == .wave)
        #expect(picker.next(from: [.wave, .shy]) == .shy)
        #expect(picker.next(from: [.wave, .shy]) == .wave)
    }

    @Test(arguments: PetActivity.allCases)
    func automaticActionsOnlyRunWhileAmbientOrIdle(activity: PetActivity) {
        let expected = activity == .ambient || activity == .idle
        #expect(MotionPolicy.allowsAutomaticFlight(activity: activity, paused: false, hidden: false, hovering: false, quiet: false, reduceMotion: false) == expected)
        #expect(MotionPolicy.allowsAmbientGesture(activity: activity, paused: false, hidden: false, hovering: false, quiet: false, reduceMotion: false) == expected)
    }

    @Test(arguments: [
        (true, false, false, false, false),
        (false, true, false, false, false),
        (false, false, true, false, false),
        (false, false, false, true, false),
        (false, false, false, false, true),
    ])
    func everySuppressionFlagBlocksAutomaticActions(flags: (Bool, Bool, Bool, Bool, Bool)) {
        let (paused, hidden, hovering, quiet, reduceMotion) = flags
        #expect(!MotionPolicy.allowsAutomaticFlight(activity: .ambient, paused: paused, hidden: hidden, hovering: hovering, quiet: quiet, reduceMotion: reduceMotion))
        #expect(!MotionPolicy.allowsAmbientGesture(activity: .idle, paused: paused, hidden: hidden, hovering: hovering, quiet: quiet, reduceMotion: reduceMotion))
    }

    @Test func cooldownAllowsFirstAndElapsedIntervalsAndResetsAfterClockRollback() {
        var cooldown = BubbleCooldown(interval: 300)
        let first = cooldown.allow(now: 1_000)
        let tooSoon = cooldown.allow(now: 1_299.999)
        let elapsed = cooldown.allow(now: 1_300)
        let rollback = cooldown.allow(now: 20)
        let afterRollback = cooldown.allow(now: 21)
        #expect(first)
        #expect(!tooSoon)
        #expect(elapsed)
        #expect(rollback)
        #expect(!afterRollback)
    }

    @Test func flightMotionUsesPhasesAndPowerAwareFrameRates() {
        #expect(FlightMotion.phase(progress: 0) == .preparing)
        #expect(FlightMotion.phase(progress: 0.119) == .preparing)
        #expect(FlightMotion.phase(progress: 0.12) == .cruising)
        #expect(FlightMotion.phase(progress: 0.819) == .cruising)
        #expect(FlightMotion.phase(progress: 0.82) == .settling)
        #expect(FlightMotion.phase(progress: 1) == .settling)
        #expect(FlightMotion.preferredFramesPerSecond(lowPower: false) == 60)
        #expect(FlightMotion.preferredFramesPerSecond(lowPower: true) == 30)
    }

    @Test func flightBankAnglesAreClampedAndQuantizedForStableLayerUpdates() {
        #expect(FlightMotion.quantizedBankAngle(.nan) == 0)
        #expect(FlightMotion.quantizedBankAngle(-1) == -0.05)
        #expect(FlightMotion.quantizedBankAngle(1) == 0.05)
        #expect(FlightMotion.quantizedBankAngle(0.0124) == 0.01)
        #expect(FlightMotion.quantizedBankAngle(0.0126) == 0.015)
        #expect(
            FlightMotion.quantizedBankAngle(0.013)
                == FlightMotion.quantizedBankAngle(0.014)
        )
    }

    @Test func springOffsetIsFiniteBoundedAndZeroOutsideOneSecond() {
        #expect(FlightMotion.springOffset(elapsed: -0.01) == .init(x: 0, y: 0))
        #expect(FlightMotion.springOffset(elapsed: 0) == .init(x: 0, y: 0))
        #expect(FlightMotion.springOffset(elapsed: 1) == .init(x: 0, y: 0))
        #expect(FlightMotion.springOffset(elapsed: 2) == .init(x: 0, y: 0))
        for step in 1..<100 {
            let offset = FlightMotion.springOffset(elapsed: Double(step) / 100)
            #expect(offset.x.isFinite && offset.y.isFinite)
            #expect((-4...4).contains(offset.x))
            #expect((-4...4).contains(offset.y))
        }
    }
}
