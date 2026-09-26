import Foundation

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

expect(PetDialogue.pride.text.replacingOccurrences(of: "\n", with: "") == "但愿我会让你感到骄傲，但愿我没有让你失望。", "user's intended quote was misspelled")
expect(PetDialogue.pride.text.contains("骄傲，\n但愿"), "long quote should break at its sentence boundary, not orphan its last word")
expect(PetDialogue.journey.text.contains("旅途，\n能和"), "journey quote should use a deliberate line break")
expect(PetDialogue.pride.duration == 8, "long quote needs eight seconds to read")
for scene in DialogueScene.allCases {
    let lines = PetDialogue.lines(for: scene)
    expect(!lines.isEmpty, "empty dialogue scene: \(scene)")
    expect(lines.allSatisfy { !$0.text.isEmpty && (3.5...8).contains($0.duration) }, "invalid dialogue duration or text")
    expect(lines.allSatisfy { $0.text.split(separator: "\n").count <= 2 }, "too many explicit bubble lines")
    var picker = DialoguePicker()
    var previous: String?
    var seen = Set<String>()
    for _ in 0..<300 {
        let selected = picker.next(for: scene)
        expect(lines.contains(selected), "picker escaped its scene")
        if lines.count > 1 { expect(selected.text != previous, "consecutive quote repetition") }
        previous = selected.text
        seen.insert(selected.text)
    }
    expect(seen.count == lines.count, "a quote is unreachable")
}
expect(PetDialogue.lines(for: .interaction).contains(PetDialogue.pride), "story quote not reachable by clicking")
expect(PetDialogue.lines(for: .ready).contains(PetDialogue.pride), "completion lost requested quote")
expect(PetDialogue.lines(for: .needsInput).allSatisfy { $0.text.contains("需要你") }, "permission hint is ambiguous")
expect(PetDialogue.lines(for: .failed).allSatisfy { $0.text.contains("工具运行失败") }, "failure hint is ambiguous")
expect(PetDialogue.lines(for: .toolRunning).allSatisfy { $0.text.contains("正在运行工具") }, "tool status is ambiguous")
expect(!PetDialogue.lines(for: .interaction).contains { $0.text.contains("本地测试") }, "diagnostic label leaked into character quotes")

if failures.isEmpty { print("PASS: dialogue catalog, durations and non-repetition"); exit(0) }
for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
exit(1)
