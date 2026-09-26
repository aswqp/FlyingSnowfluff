import Foundation
import FlyingSnowfluffCore

private struct TestSuite {
    private(set) var failures: [String] = []

    mutating func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message) }
    }

    mutating func run() throws {
        let negativeFrame = Rect2D(x: -1728, y: -120, width: 1728, height: 1117)
        let safe = negativeFrame.insetBy(dx: 96, dy: 112)
        var planner = FlightPlanner(seed: 0xA11CE)
        for pathIndex in 0..<100 {
            let path = planner.makePath(in: negativeFrame, marginX: 96, marginY: 112)
            for step in 0...240 {
                check(safe.contains(path.point(at: Double(step) / 240)), "path \(pathIndex) escaped safe frame")
            }
        }

        let secondDisplay = Rect2D(x: 1440, y: -300, width: 2560, height: 1440)
        var secondPlanner = FlightPlanner(seed: 42)
        let longPath = secondPlanner.makePath(in: secondDisplay, marginX: 80, marginY: 100)
        check(secondDisplay.contains(longPath.point(at: 0)), "path start outside selected display")
        check(secondDisplay.contains(longPath.point(at: 1)), "path end outside selected display")
        check(longPath.point(at: 0).distance(to: longPath.point(at: 1)) > 300, "path travel too short")

        let alignedDisplay = Rect2D(x: 1440, y: 0, width: 1920, height: 900)
        let offsetDisplay = Rect2D(x: 1440, y: 180, width: 1920, height: 1080)
        let primaryDisplay = Rect2D(x: 0, y: 0, width: 1440, height: 900)
        check(primaryDisplay.formsSolidBoundingUnion(with: alignedDisplay), "aligned displays were rejected for cross-display flight")
        check(!primaryDisplay.formsSolidBoundingUnion(with: offsetDisplay), "offscreen hole in display union was accepted")

        var scheduler = ActionScheduler(seed: 7)
        for _ in 0..<200 {
            check((120...300).contains(scheduler.nextFlightDelay(reduceMotion: false)), "normal flight delay outside contract")
            check((4...9).contains(scheduler.nextFlightDuration(reduceMotion: false)), "normal flight duration outside contract")
            check((60...150).contains(scheduler.nextAmbientDelay()), "ambient delay outside contract")
        }
        var reducedScheduler = ActionScheduler(seed: 9)
        for _ in 0..<100 {
            check((240...480).contains(reducedScheduler.nextFlightDelay(reduceMotion: true)), "reduced motion delay outside contract")
            check((7...12).contains(reducedScheduler.nextFlightDuration(reduceMotion: true)), "reduced motion duration outside contract")
        }

        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var priority = PetStateCoordinator()
        priority.receive(.working, at: start)
        priority.receive(.ready, at: start.addingTimeInterval(1))
        priority.receive(.failed, at: start.addingTimeInterval(2))
        priority.receive(.needsInput, at: start.addingTimeInterval(3))
        check(priority.current(at: start.addingTimeInterval(4)) == .needsInput, "state priority incorrect")

        var waiting = PetStateCoordinator()
        waiting.receive(.needsInput, at: start)
        check(waiting.current(at: start.addingTimeInterval(3_600)) == .needsInput, "needsInput did not persist")
        waiting.receive(.working, at: start.addingTimeInterval(3_601))
        check(waiting.current(at: start.addingTimeInterval(3_602)) == .working, "prompt did not release needsInput")

        var failed = PetStateCoordinator()
        failed.receive(.working, at: start)
        failed.receive(.failed, at: start.addingTimeInterval(1))
        check(failed.current(at: start.addingTimeInterval(10.9)) == .failed, "failure expired too early")
        check(failed.current(at: start.addingTimeInterval(11.1)) == .working, "failure did not expire")

        var ready = PetStateCoordinator()
        ready.receive(.ready, at: start)
        check(ready.current(at: start.addingTimeInterval(7.9)) == .ready, "ready expired too early")
        check(ready.current(at: start.addingTimeInterval(8.1)) == .ambient, "ready did not expire")

        var stale = PetStateCoordinator()
        stale.receive(.working, at: start)
        check(stale.current(at: start.addingTimeInterval(599)) == .working, "working expired too early")
        check(stale.current(at: start.addingTimeInterval(601)) == .ambient, "stale working did not expire")

        check(
            CodexLinkPresentation.statusTitle(activity: .ambient, hasReceivedEvent: false)
                == "Codex 联动：尚未收到事件",
            "missing-event status title incorrect"
        )
        let expectedLinkTitles: [(PetActivity, String)] = [
            (.working, "Codex 联动：正在工作"),
            (.toolRunning, "Codex 联动：正在运行工具"),
            (.needsInput, "Codex 联动：等待你确认"),
            (.failed, "Codex 联动：运行失败"),
            (.ready, "Codex 联动：已完成"),
            (.ambient, "Codex 联动：已回到日常模式"),
            (.idle, "Codex 联动：已回到日常模式")
        ]
        for (activity, expectedTitle) in expectedLinkTitles {
            check(
                CodexLinkPresentation.statusTitle(activity: activity, hasReceivedEvent: true) == expectedTitle,
                "link status title incorrect for \(activity)"
            )
        }
        check(
            CodexLinkPresentation.recencyTitle(lastEventAt: nil, now: start) == "最近事件：无",
            "nil event recency title incorrect"
        )
        check(
            CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(3)) == "最近事件：刚刚",
            "recent event title incorrect"
        )
        check(
            CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(42)) == "最近事件：42 秒前",
            "seconds event title incorrect"
        )
        check(
            CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(125)) == "最近事件：2 分钟前",
            "minutes event title incorrect"
        )

        let menuPresentation = StatusMenuPresentation.make(
            settings: PetSettings(
                height: 208,
                isPaused: true,
                crossDisplays: true,
                reduceMotion: true,
                launchAtLogin: false,
                isMuted: true
            ),
            isHidden: true,
            loginItemEnabled: false,
            activity: .toolRunning,
            lastHookEventAt: start,
            now: start.addingTimeInterval(6)
        )
        check(menuPresentation.pauseTitle == "继续", "paused menu title incorrect")
        check(menuPresentation.hideTitle == "显示", "hidden menu title incorrect")
        check(menuPresentation.crossDisplays, "cross-display menu state missing")
        check(menuPresentation.reduceMotion, "reduce-motion menu state missing")
        check(!menuPresentation.loginItemEnabled, "login menu state incorrect")
        check(menuPresentation.linkStatusTitle == "Codex 联动：正在运行工具", "menu link status incorrect")
        check(menuPresentation.lastEventTitle == "最近事件：6 秒前", "menu event recency incorrect")

        let privateInput = Data(#"{"session_id":"s-1","turn_id":"t-9","prompt":"extremely private"}"#.utf8)
        let envelope = HookEnvelopeParser.parse(privateInput, forcedEvent: .userPromptSubmit, timestamp: Date(timeIntervalSince1970: 123))
        check(envelope?.event == .working, "prompt mapping incorrect")
        check(envelope?.sessionID == "s-1" && envelope?.turnID == "t-9", "identifier mapping incorrect")
        let encodedEnvelope = try envelope.map { try JSONEncoder().encode($0) }
        check(encodedEnvelope.map { !String(decoding: $0, as: UTF8.self).contains("private") } == true, "prompt text leaked")

        check(HookEnvelopeParser.parse(Data(#"{"tool_response":{"isError":true,"exit_code":1}}"#.utf8), forcedEvent: .postToolUse)?.event == .failed, "tool failure mapping incorrect")
        check(HookEnvelopeParser.parse(Data(#"{"tool_response":{"isError":false,"exit_code":0}}"#.utf8), forcedEvent: .postToolUse)?.event == .working, "tool success mapping incorrect")
        check(HookEnvelopeParser.parse(Data("not json".utf8), forcedEvent: .preToolUse) == nil, "invalid JSON accepted")
        check(HookEnvelopeParser.parse(Data(repeating: 65, count: 65_537), forcedEvent: .stop) == nil, "oversized hook accepted")

        let defaults = PetSettings.default
        check(defaults.height == 208 && defaults.launchAtLogin && defaults.isMuted, "settings defaults incorrect")
        let small = try JSONDecoder().decode(PetSettings.self, from: Data(#"{"height":12,"isPaused":false,"crossDisplays":true,"reduceMotion":false,"launchAtLogin":true,"isMuted":true}"#.utf8))
        let large = try JSONDecoder().decode(PetSettings.self, from: Data(#"{"height":900,"isPaused":false,"crossDisplays":true,"reduceMotion":false,"launchAtLogin":true,"isMuted":true}"#.utf8))
        check(small.height == 176 && large.height == 320, "settings height clamp incorrect")
        var assignedHeight = PetSettings.default
        assignedHeight.height = 12
        check(assignedHeight.height == 176, "assigned small settings height was not clamped")
        assignedHeight.height = 900
        check(assignedHeight.height == 320, "assigned large settings height was not clamped")

        let defaultLayout = PetWindowLayout.make()
        check(defaultLayout.petRect == Rect2D(x: 0, y: 0, width: 192, height: 208), "default pet layout stretched or mis-sized")
        let bubbleLayout = PetWindowLayout.make(containerWidth: 320, bubbleHeight: 44, spacing: 12)
        check(bubbleLayout.petRect == Rect2D(x: 64, y: 56, width: 192, height: 208), "pet layout not centered under bubble")
        check(bubbleLayout.windowSize == Size2D(width: 320, height: 264), "window size does not include bubble and gap")
        for height in [176.0, 208, 256, 320] {
            let layout = PetWindowLayout.make(petHeight: height, containerWidth: 400)
            check(abs(layout.petRect.width * 208 - layout.petRect.height * 192) < 0.000_001, "pet layout aspect ratio incorrect for height \(height)")
        }

        let aligned = Rect2D(x: -1.26, y: -0.24, width: 3.51, height: 2.49).pixelAligned(backingScale: 2)
        check(aligned == Rect2D(x: -1.5, y: 0, width: 4, height: 2.5), "negative-coordinate Retina alignment incorrect")
        let invertedAligned = Rect2D(x: 3.2, y: -1.1, width: -1.1, height: -0.1).pixelAligned(backingScale: 2)
        check(invertedAligned.width >= 0 && invertedAligned.height >= 0, "pixel alignment produced negative size")

        let settingsSuiteName = "FlyingSnowfluffDirectTests.\(UUID().uuidString)"
        guard let settingsDefaults = UserDefaults(suiteName: settingsSuiteName) else {
            throw NSError(domain: "FlyingSnowfluffDirectTests", code: 1)
        }
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuiteName) }
        let legacyData = Data(#"{"height":181,"isPaused":true,"crossDisplays":true,"reduceMotion":true,"launchAtLogin":false,"isMuted":false}"#.utf8)
        settingsDefaults.set(legacyData, forKey: "settings.v1")
        let migrated = PetSettingsStore.load(from: settingsDefaults)
        check(migrated.height == 208, "legacy fallback did not choose nearest height tier")
        check(migrated.isPaused && migrated.crossDisplays && migrated.reduceMotion && !migrated.launchAtLogin && !migrated.isMuted, "legacy migration did not preserve preferences")
        check(settingsDefaults.data(forKey: "settings.v1") == legacyData, "legacy settings were deleted during migration")
        let v3Data = settingsDefaults.data(forKey: "settings.v3")
        check(v3Data != nil, "migration did not save v3 settings")
        let v3JSON = v3Data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check(v3JSON?["schemaVersion"] as? Int == 3, "v3 settings JSON lacks schemaVersion 3")
        let v2Preferred = PetSettings(height: 320, isPaused: false, crossDisplays: false, reduceMotion: false, launchAtLogin: true, isMuted: true)
        PetSettingsStore.save(v2Preferred, to: settingsDefaults)
        check(PetSettingsStore.load(from: settingsDefaults) == v2Preferred, "v2 settings did not take priority over v1")
    }
}

private var suite = TestSuite()
do {
    try suite.run()
} catch {
    suite.check(false, "unexpected thrown error: \(error)")
}

if suite.failures.isEmpty {
    print("PASS: core contract suite")
    exit(0)
}
for failure in suite.failures { fputs("FAIL: \(failure)\n", stderr) }
exit(1)
