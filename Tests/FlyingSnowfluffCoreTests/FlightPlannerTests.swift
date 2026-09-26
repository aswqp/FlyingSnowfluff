import Testing
@testable import FlyingSnowfluffCore

@Suite("Flight planner")
struct FlightPlannerTests {
    @Test func bezierPathStaysInsideSafeFrameWithNegativeCoordinates() {
        let frame = Rect2D(x: -1728, y: -120, width: 1728, height: 1117)
        let safe = frame.insetBy(dx: 96, dy: 112)
        var planner = FlightPlanner(seed: 0xA11CE)

        for _ in 0..<100 {
            let path = planner.makePath(in: frame, marginX: 96, marginY: 112)
            for step in 0...240 {
                let point = path.point(at: Double(step) / 240)
                #expect(safe.contains(point), "\(point) escaped \(safe)")
            }
        }
    }

    @Test func pathBeginsAndEndsInsideSelectedDisplay() {
        let display = Rect2D(x: 1440, y: -300, width: 2560, height: 1440)
        var planner = FlightPlanner(seed: 42)
        let path = planner.makePath(in: display, marginX: 80, marginY: 100)

        #expect(display.contains(path.point(at: 0)))
        #expect(display.contains(path.point(at: 1)))
        #expect(path.point(at: 0).distance(to: path.point(at: 1)) > 300)
    }

    @Test func flightIntervalsAndDurationsStayWithinContract() {
        var scheduler = ActionScheduler(seed: 7)
        for _ in 0..<200 {
            #expect((120...300).contains(scheduler.nextFlightDelay(reduceMotion: false)))
            #expect((4...9).contains(scheduler.nextFlightDuration(reduceMotion: false)))
            #expect((60...150).contains(scheduler.nextAmbientDelay()))
        }
    }

    @Test func reduceMotionUsesShorterSlowerFlightContract() {
        var scheduler = ActionScheduler(seed: 9)
        for _ in 0..<100 {
            #expect((240...480).contains(scheduler.nextFlightDelay(reduceMotion: true)))
            #expect((7...12).contains(scheduler.nextFlightDuration(reduceMotion: true)))
        }
    }

    @Test func crossDisplayBoundingUnionRejectsOffscreenHoles() {
        let primary = Rect2D(x: 0, y: 0, width: 1440, height: 900)
        let aligned = Rect2D(x: 1440, y: 0, width: 1920, height: 900)
        let verticallyOffset = Rect2D(x: 1440, y: 180, width: 1920, height: 1080)

        #expect(primary.formsSolidBoundingUnion(with: aligned))
        #expect(!primary.formsSolidBoundingUnion(with: verticallyOffset))
    }
}
