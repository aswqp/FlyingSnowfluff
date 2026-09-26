@preconcurrency import AppKit
import QuartzCore
import Foundation

// Export the already-approved native renderer into the existing v1 skin
// contract. No character generation, App preference, hook or UI modification.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let atlas = try SpriteAtlas(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNOWFLUFF_SKIN_EXPORT_DIR"]!)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let view = SpriteView(atlas: atlas)
view.frame = NSRect(x: 0, y: 0, width: 192, height: 208)
let panel = NSPanel(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.contentView = view
panel.orderFrontRegardless()
view.layoutSubtreeIfNeeded()
precondition(view.hasLivelyArtwork)

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
}
func capture(_ row: Int, _ column: Int) throws {
    guard let presentation = view.layer?.presentation() else {
        fatalError("Native animation export requires WindowServer presentation layers; refusing static fallback")
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 384, pixelsHigh: 416,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // SpriteView uses top-left geometry; the bitmap context starts bottom-left.
    context.translateBy(x: 0, y: 416)
    context.scaleBy(x: 2, y: -2)
    if row == 4 {
        // Keep the existing jumping row's lift/land semantics when baked;
        // translate the whole rendered pose without stretching the artwork.
        context.translateBy(x: 0, y: [0.0, -3.0, -7.0, -3.0, 0.0][column])
    }
    presentation.render(in: context)
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(row)-\(column).png"))
}

let names = ["idle", "flyRight", "flyLeft", "wave", "celebrate", "failed", "waiting", "working", "celebrate"]
let times: [[Double]] = [
    [0, 0.8, 1.6, 2.4, 5.55, 5.7],
    [0, 0.5, 0.75, 1.2, 1.8, 2.4, 3.1, 3.7],
    [0, 0.5, 0.75, 1.2, 1.8, 2.4, 3.1, 3.7],
    [0, 0.4, 1.0, 1.72],
    [0, 0.25, 0.6, 0.9, 1.4],
    [0, 0.15, 0.35, 0.48, 0.7, 1.0, 1.4, 1.95],
    [0, 0.3, 0.6, 0.9, 1.2, 1.7],
    [0, 1.2, 2.4, 5.55, 10.3/0.65, 16.9],
    [0, 0.2, 0.4, 0.6, 0.9, 1.4]
]
var count = 0
for row in 0..<9 {
    view.playMotion("idle")
    let start = CACurrentMediaTime()
    view.playMotion(names[row], at: start)
    for (column, elapsed) in times[row].enumerated() {
        view.animationsEnabled = !(row == 0 && column == 0)
        view.updateMotion(at: start + elapsed)
        if row == 1 || row == 2 {
            view.setFlightPose(progress: elapsed/3.8, right: row == 1)
        }
        pump(column == 0 ? 0.06 : row == 6 ? 0.78 : 0.24)
        if row == 0 || row == 6 {
            let presentation = view.layer?.presentation()
            let y = presentation?.sublayers?.first?.sublayers?.first?.transform.m42
            print("sample \(row)-\(column): presentation=\(presentation != nil), breath=\(y ?? -999)")
        }
        try capture(row, column)
        count += 1
    }
}
panel.orderOut(nil)
precondition(count == 57)
print("PASS: exported \(count) native-rendered 384x416 RGBA frames; no Codex settings or hooks changed")
