import Foundation

public enum CodexLinkPresentation {
    public static func statusTitle(activity: PetActivity, hasReceivedEvent: Bool) -> String {
        guard hasReceivedEvent else { return "Codex 联动：尚未收到事件" }
        switch activity {
        case .working: return "Codex 联动：正在工作"
        case .toolRunning: return "Codex 联动：正在运行工具"
        case .needsInput: return "Codex 联动：等待你确认"
        case .failed: return "Codex 联动：运行失败"
        case .ready: return "Codex 联动：已完成"
        case .ambient, .idle: return "Codex 联动：已回到日常模式"
        }
    }

    public static func recencyTitle(lastEventAt: Date?, now: Date = Date()) -> String {
        guard let lastEventAt else { return "最近事件：无" }
        let elapsed = max(0, Int(now.timeIntervalSince(lastEventAt).rounded(.down)))
        if elapsed < 5 { return "最近事件：刚刚" }
        if elapsed < 60 { return "最近事件：\(elapsed) 秒前" }
        if elapsed < 3_600 { return "最近事件：\(elapsed / 60) 分钟前" }
        return "最近事件：\(elapsed / 3_600) 小时前"
    }
}

public struct StatusMenuPresentation: Equatable, Sendable {
    public let pauseTitle: String
    public let hideTitle: String
    public let crossDisplays: Bool
    public let reduceMotion: Bool
    public let loginItemEnabled: Bool
    public let linkStatusTitle: String
    public let lastEventTitle: String

    public static func make(
        settings: PetSettings,
        isHidden: Bool,
        loginItemEnabled: Bool,
        activity: PetActivity,
        lastHookEventAt: Date?,
        now: Date = Date()
    ) -> StatusMenuPresentation {
        StatusMenuPresentation(
            pauseTitle: settings.isPaused ? "继续" : "暂停",
            hideTitle: isHidden ? "显示" : "隐藏",
            crossDisplays: settings.crossDisplays,
            reduceMotion: settings.reduceMotion,
            loginItemEnabled: loginItemEnabled,
            linkStatusTitle: CodexLinkPresentation.statusTitle(
                activity: activity,
                hasReceivedEvent: lastHookEventAt != nil
            ),
            lastEventTitle: CodexLinkPresentation.recencyTitle(lastEventAt: lastHookEventAt, now: now)
        )
    }
}
