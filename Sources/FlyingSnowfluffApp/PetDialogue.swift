import Foundation

enum DialogueScene: CaseIterable {
    case interaction, flight, working, toolRunning, needsInput, failed, ready, reappear
}

struct DialogueLine: Equatable {
    let text: String
    let duration: TimeInterval

    init(_ text: String, duration: TimeInterval = 3.5) {
        self.text = text
        self.duration = duration
    }
}

/// Short textual excerpts only; attribution and wording notes are in
/// Packaging/经典台词与来源.md. Functional status text is not a game quotation.
enum PetDialogue {
    static let pride = DialogueLine("但愿我会让你感到骄傲，\n但愿我没有让你失望。", duration: 8)
    static let journey = DialogueLine("最后这段旅途，\n能和你一起走，真是太好啦！", duration: 7)
    static let protection = DialogueLine("未来，就由我来保护你吧。", duration: 5)
    static let entrance = DialogueLine("幽灵登台！")
    static let greeting = DialogueLine("你能看见我吗？")

    static func lines(for scene: DialogueScene) -> [DialogueLine] {
        switch scene {
        case .interaction:
            return [greeting, entrance, protection, journey, pride]
        case .flight:
            return [DialogueLine("浮游星海~")]
        case .working:
            return [DialogueLine("这次，交给我。")]
        case .toolRunning:
            return [DialogueLine("这次，交给我。\n正在运行工具……")]
        case .needsInput:
            return [DialogueLine("需要你看一眼这里。", duration: 6)]
        case .failed:
            return [DialogueLine("小失误……\n工具运行失败，请查看 Codex。", duration: 6)]
        case .ready:
            return [pride, journey]
        case .reappear:
            return [entrance, greeting]
        }
    }
}

struct DialoguePicker {
    private var previousText: String?

    mutating func next(for scene: DialogueScene) -> DialogueLine {
        let lines = PetDialogue.lines(for: scene)
        let alternatives = lines.filter { $0.text != previousText }
        let line = alternatives.randomElement() ?? lines[0]
        previousText = line.text
        return line
    }
}
