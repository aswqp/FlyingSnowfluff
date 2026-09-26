@preconcurrency import AppKit
import FlyingSnowfluffCore
import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func pumpMainRunLoop(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
    }
}

private func visibleBubbleText() -> String? {
    NSApp.windows.compactMap { $0.contentView as? PetContentView }
        .flatMap { $0.subviews.compactMap { $0 as? NSTextField } }
        .first { !$0.isHidden }?.stringValue
}

guard CommandLine.arguments.count == 2 else {
    fputs("FAIL: expected 2x spritesheet path\n", stderr)
    exit(2)
}

do {
    _ = NSApplication.shared
    let suite = "snowfluff.behavior.qa.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let atlas = try SpriteAtlas(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    let controller = PetController(atlas: atlas, defaults: defaults)
    let statusMenu = StatusMenuController(controller: controller)

    expect(controller.qaContextMenu === statusMenu.qaMenu, "status item and pet do not share one menu")
    expect(statusMenu.qaMenu.item(withTitle: "动作预览") != nil, "action preview menu is missing")
    expect(statusMenu.qaMenu.item(withTitle: "安静陪伴") != nil, "quiet companionship menu is missing")
    statusMenu.menuWillOpen(statusMenu.qaMenu)
    expect(statusMenu.qaLinkStatusTitle == "Codex 联动：尚未收到事件", "initial link status incorrect")
    expect(statusMenu.qaLastEventTitle == "最近事件：无", "initial event recency incorrect")
    expect(
        StatusMenuController.codexLinkHelpText.contains("配置共 6 条"),
        "Codex link help did not explain the six configured commands"
    )
    expect(
        StatusMenuController.codexLinkHelpText.contains("页面可能只列 5 项"),
        "Codex link help did not explain the five-item UI compatibility boundary"
    )

    controller.toggleHidden()
    expect(controller.isHidden, "controller did not enter hidden state")
    expect(!controller.qaSnapshot().isWindowVisible, "hidden window remained visible")

    let hookTimeBeforeShow = controller.qaLastHookEventAt
    controller.show()
    expect(!controller.isHidden, "show did not clear hidden state")
    expect(controller.qaSnapshot().isWindowVisible, "show did not order window front")
    expect(controller.qaShowTransitionCount == 1, "hidden-to-visible transition did not show one return bubble")
    expect(controller.qaLastHookEventAt == hookTimeBeforeShow, "show changed real Codex event time")

    controller.show()
    expect(controller.qaShowTransitionCount == 1, "idempotent show repeated the return bubble")
    expect(controller.qaSnapshot().isWindowVisible, "second show hid the window")

    controller.setPaused(true)
    controller.toggleHidden()
    statusMenu.menuWillOpen(statusMenu.qaMenu)
    expect(statusMenu.qaPauseTitle == "继续", "pause menu did not refresh")
    expect(statusMenu.qaHideTitle == "显示", "hidden menu did not refresh")
    controller.show()
    controller.setPaused(false)

    controller.runLocalLinkTest()
    expect(visibleBubbleText()?.hasPrefix("本地测试：") == true, "local test must retain its diagnostic label")
    expect(controller.qaCurrentActivity == .toolRunning, "local link test did not enter tool-running state")
    expect(controller.qaSnapshot().animationRow == 7, "local link test did not select working animation")
    expect(controller.qaLastHookEventAt == nil, "local link test impersonated a real hook event")
    pumpMainRunLoop(for: 2.2)
    expect(controller.qaCurrentActivity == .ready, "local link test did not enter ready state")
    expect(controller.qaSnapshot().animationRow == 8, "local link test did not select completion animation")
    expect(controller.qaLastHookEventAt == nil, "local completion impersonated a real hook event")

    let realEventTime = Date()
    controller.receive(HookEnvelope(event: .working, sessionID: "qa", turnID: "qa-turn", timestamp: realEventTime))
    expect(visibleBubbleText()?.contains("这次，交给我。") == true, "working bubble is not the selected game quote")
    expect(controller.qaCurrentActivity == .working, "real hook event did not enter working state")
    expect(controller.qaMotionFrame == "neutral", "working companion must use relaxed hands, not the rejected raised-paws pose")
    let recordedEventTime = controller.qaLastHookEventAt
    expect(
        recordedEventTime.map { abs($0.timeIntervalSince(realEventTime)) < 0.001 } == true,
        "real hook receipt time was not recorded within 1 ms"
    )
    statusMenu.menuWillOpen(statusMenu.qaMenu)
    expect(statusMenu.qaLinkStatusTitle == "Codex 联动：正在工作", "menu did not show real working state")
    expect(statusMenu.qaLastEventTitle == "最近事件：刚刚", "menu did not show real event recency")

    let firstWorkBubble = visibleBubbleText()
    controller.receive(HookEnvelope(event: .toolRunning, sessionID: "qa", turnID: "tool", timestamp: realEventTime))
    expect(visibleBubbleText() == firstWorkBubble, "tool hook bypassed shared dialogue cooldown")
    controller.receive(HookEnvelope(event: .working, sessionID: "qa", turnID: "tool", timestamp: realEventTime))
    expect(visibleBubbleText() == firstWorkBubble, "post-tool hook flooded the working bubble")

    controller.startFlight()
    expect(!controller.isFlying, "automatic flight interrupted Codex work")

    controller.previewGesture(.wave)
    expect(controller.qaSnapshot().animationRow == 3,"manual wave did not interrupt work briefly")
    pumpMainRunLoop(for: 2)
    expect(controller.qaCurrentActivity == .working && controller.qaSnapshot().animationRow == 7,"manual gesture failed to restore true working state")
    expect(controller.qaLastHookEventAt == recordedEventTime,"manual gesture changed hook time")
    controller.previewGesture(.shy)
    controller.receive(HookEnvelope(event:.working,sessionID:"qa",turnID:"same",timestamp:Date()))
    expect(controller.qaSnapshot().animationRow == 7,"same-state real event left gesture stuck")
    controller.setQuietCompanionship(true)
    expect(!controller.qaAutomaticActionsScheduled,"quiet mode retained automatic tasks")
    controller.setQuietCompanionship(false)
    controller.qaSetSystemReduceMotion(true)
    expect(!controller.qaFrameTimerActive && !controller.qaAutomaticActionsScheduled,"reduce-motion retained unnecessary updates")
    controller.qaSetSystemReduceMotion(false)
    expect(controller.qaFrameTimerActive && controller.qaAutomaticActionsScheduled,"leaving system reduce-motion did not restore schedules")
    controller.startFlight(userInitiated:true)
    expect(controller.isFlying,"explicit flight should be available during work")
    controller.toggleHidden()
    expect(!controller.isFlying && !controller.qaFrameTimerActive,"hidden pet continued flight/render updates")
    controller.show()
    expect(controller.qaFrameTimerActive,"reopened pet did not resume rendering")
    expect(controller.qaSnapshot().animationRow == 7,"reopened pet lost true working pose")

    controller.receive(HookEnvelope(event: .ready, sessionID: "qa", turnID: "ready", timestamp: Date()))
    expect(visibleBubbleText()?.contains("但愿") == true || visibleBubbleText()?.contains("旅途") == true,
        "completion did not select a story quote")
    controller.receive(HookEnvelope(event: .failed, sessionID: "qa", turnID: "failed", timestamp: Date()))
    expect(visibleBubbleText()?.contains("小失误") == true, "failure did not select game quote")
    expect(visibleBubbleText()?.contains("工具运行失败") == true, "failure status must remain explicit")
    controller.receive(HookEnvelope(event: .needsInput, sessionID: "qa", turnID: "input", timestamp: Date()))
    expect(visibleBubbleText()?.contains("需要你") == true, "permission hint was replaced with ambiguous dialogue")
    controller.stop()
} catch {
    failures.append("unexpected error: \(error)")
}

if failures.isEmpty {
    print("PASS: menu and Codex link runtime suite")
    exit(0)
}
for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
exit(1)
