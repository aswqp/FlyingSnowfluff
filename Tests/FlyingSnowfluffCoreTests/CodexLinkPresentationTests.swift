import Foundation
import Testing
@testable import FlyingSnowfluffCore

@Test func codexLinkStatusTitlesCoverEveryActivity() {
    #expect(CodexLinkPresentation.statusTitle(activity: .ambient, hasReceivedEvent: false) == "Codex 联动：尚未收到事件")
    #expect(CodexLinkPresentation.statusTitle(activity: .working, hasReceivedEvent: true) == "Codex 联动：正在工作")
    #expect(CodexLinkPresentation.statusTitle(activity: .toolRunning, hasReceivedEvent: true) == "Codex 联动：正在运行工具")
    #expect(CodexLinkPresentation.statusTitle(activity: .needsInput, hasReceivedEvent: true) == "Codex 联动：等待你确认")
    #expect(CodexLinkPresentation.statusTitle(activity: .failed, hasReceivedEvent: true) == "Codex 联动：运行失败")
    #expect(CodexLinkPresentation.statusTitle(activity: .ready, hasReceivedEvent: true) == "Codex 联动：已完成")
    #expect(CodexLinkPresentation.statusTitle(activity: .idle, hasReceivedEvent: true) == "Codex 联动：已回到日常模式")
}

@Test func codexLinkRecencyUsesStableHumanScaleBuckets() {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(CodexLinkPresentation.recencyTitle(lastEventAt: nil, now: start) == "最近事件：无")
    #expect(CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(3)) == "最近事件：刚刚")
    #expect(CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(42)) == "最近事件：42 秒前")
    #expect(CodexLinkPresentation.recencyTitle(lastEventAt: start, now: start.addingTimeInterval(125)) == "最近事件：2 分钟前")
}

@Test func statusMenuPresentationReflectsSettingsAndLinkState() {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let presentation = StatusMenuPresentation.make(
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

    #expect(presentation.pauseTitle == "继续")
    #expect(presentation.hideTitle == "显示")
    #expect(presentation.crossDisplays)
    #expect(presentation.reduceMotion)
    #expect(!presentation.loginItemEnabled)
    #expect(presentation.linkStatusTitle == "Codex 联动：正在运行工具")
    #expect(presentation.lastEventTitle == "最近事件：6 秒前")
}
