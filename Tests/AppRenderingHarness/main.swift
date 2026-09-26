@preconcurrency import AppKit
import FlyingSnowfluffCore
import Foundation

private struct RenderingChecks {
    private(set) var failures: [String] = []

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message) }
    }

    mutating func run() throws {
        guard CommandLine.arguments.count == 3 else {
            failures.append("usage: app-rendering-tests app-2x.png fallback-1x.png")
            return
        }

        let highResolutionURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fallbackURL = URL(fileURLWithPath: CommandLine.arguments[2])

        let highResolution = try SpriteAtlas(url: highResolutionURL)
        expect(highResolution.metrics.pixelWidth == 3_072, "2x atlas width mismatch")
        expect(highResolution.metrics.pixelHeight == 3_744, "2x atlas height mismatch")
        expect(highResolution.metrics.cellPixelWidth == 384, "2x cell width mismatch")
        expect(highResolution.metrics.cellPixelHeight == 416, "2x cell height mismatch")
        expect(highResolution.pixelScale == 2, "2x atlas scale not detected")
        expect(highResolution.usesSplitFrames, "2x atlas did not select memory-safe split frames")
        expect(highResolution.frame(row: 0, column: 0)?.width == 384, "2x frame crop width mismatch")
        expect(highResolution.frame(row: 0, column: 0)?.height == 416, "2x frame crop height mismatch")
        expect(!highResolution.isOpaque(row: 0, column: 0, normalizedX: 0.01, normalizedY: 0.01), "transparent frame corner became interactive")
        expect(highResolution.isOpaque(row: 0, column: 0, normalizedX: 0.5, normalizedY: 0.5), "visible character center is not interactive")

        let fallback = try SpriteAtlas(url: fallbackURL)
        expect(fallback.metrics.pixelWidth == 1_536, "1x atlas width mismatch")
        expect(fallback.metrics.cellPixelWidth == 192, "1x cell width mismatch")
        expect(fallback.pixelScale == 1, "1x atlas scale not detected")

        let preferred = try SpriteAtlas.loadBest(candidates: [highResolutionURL, fallbackURL])
        expect(preferred.pixelScale == 2, "valid 2x atlas was not preferred")

        let missing = highResolutionURL.deletingLastPathComponent().appendingPathComponent("missing.png")
        let recovered = try SpriteAtlas.loadBest(candidates: [missing, fallbackURL])
        expect(recovered.pixelScale == 1, "missing 2x atlas did not fall back to 1x")

        let invalidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flying-snowfluff-invalid-atlas-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: invalidURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        let invalidRecovered = try SpriteAtlas.loadBest(candidates: [invalidURL, fallbackURL])
        expect(invalidRecovered.pixelScale == 1, "invalid 2x atlas did not fall back to 1x")

        // A missing middle split frame must fall back to the atlas, not vanish.
        let damaged = FileManager.default.temporaryDirectory.appendingPathComponent("snowfluff-split-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:damaged,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:damaged) }
        let damagedAtlas=damaged.appendingPathComponent("spritesheet.png")
        try FileManager.default.copyItem(at:fallbackURL,to:damagedAtlas)
        let split=damaged.appendingPathComponent("frames@1x")
        try FileManager.default.copyItem(at:fallbackURL.deletingLastPathComponent().appendingPathComponent("frames@1x"),to:split)
        try FileManager.default.removeItem(at:split.appendingPathComponent("r4-c3.png"))
        let restored=try SpriteAtlas(url:damagedAtlas)
        expect(!restored.usesSplitFrames && restored.frame(row:4,column:3) != nil,"middle-frame damage did not recover to full atlas")

        let content = PetContentView(atlas: highResolution, petHeight: 208)
        expect(content.spriteView.hasLivelyArtwork, "lively speech-anchor regression did not load its fixture")
        expect(abs(content.spriteView.speechTopInset - 42) < 0.01,
            "speech anchor ignored calibrated artwork top or read upside-down alpha")
        expect(content.frame.size == NSSize(width: 280, height: 266), "default window layout mismatch")
        expect(content.spriteView.frame == NSRect(x: 44, y: 58, width: 192, height: 208), "default pet was stretched or not centered")
        let sharedContextMenu = NSMenu(title: "飞行雪绒测试菜单")
        var contextMenuPreparationCount = 0
        content.installContextMenu(sharedContextMenu) {
            contextMenuPreparationCount += 1
        }
        expect(content.spriteView.menu === sharedContextMenu, "pet drawing area did not retain the shared context menu")
        let contextEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 96, y: 104),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        if let contextEvent {
            _ = content.spriteView.menu(for: contextEvent)
        }
        expect(contextMenuPreparationCount == 1, "right-click menu did not refresh immediately before opening")
        for height in [176.0, 208, 256, 320] {
            content.updatePetHeight(height)
            let sprite = content.spriteView.frame
            let expectedRatio = 192.0 / 208.0
            let ratioError = abs(sprite.width / sprite.height - expectedRatio) / expectedRatio
            expect(ratioError <= 0.02, "pet aspect ratio exceeded 2% tolerance at height \(height)")
            expect(abs(sprite.midX - content.bounds.midX) <= 0.5, "pet was not pixel-centered at height \(height)")
            for scene in DialogueScene.allCases {
                for line in PetDialogue.lines(for: scene) {
                    content.showBubble(line.text, duration: line.duration)
                    guard let field = content.subviews.compactMap({ $0 as? NSTextField }).first else {
                        expect(false, "bubble field missing"); continue
                    }
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    let text = NSAttributedString(string: line.text, attributes: [
                        .font: field.font!, .paragraphStyle: paragraph
                    ])
                    let needed = text.boundingRect(with: NSSize(width: field.bounds.width - 8, height: 1_000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
                    expect(ceil(needed.height) <= field.bounds.height - 4,
                        "dialogue cropped at \(height) pt: \(scene) requires \(needed.height)")
                    expect(field.maximumNumberOfLines == 2 && field.font?.pointSize == 14,
                        "existing bubble typography changed")
                    if let bubble = field as? PetSpeechBubble {
                        let actual = text.boundingRect(with: NSSize(width: bubble.textRect.width, height: 1_000),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
                        expect(ceil(actual.height) <= bubble.textRect.height && ceil(actual.height) <= 36,
                            "dialogue did not fit two padded lines: \(scene)")
                        expect(bubble.hitTest(NSPoint(x: bubble.bounds.midX, y: bubble.bounds.midY)) == nil, "bubble intercepted desktop clicks")
                    }
                    // Neutral artwork starts at row 102 in the calibrated 416px
                    // source, not at the sprite container's transparent top.
                    let visibleHeadY = sprite.minY + sprite.height * 102 / 416
                    let gap = visibleHeadY - field.frame.maxY
                    expect((2...22).contains(gap),
                        "bubble is detached from visible head at \(height) pt: \(gap) pt")
                    expect(content.bounds.contains(field.frame), "bubble escaped window at \(height) pt")
                    if let color = field.textColor?.usingColorSpace(.sRGB) {
                        expect(color.redComponent > color.greenComponent && color.redComponent < 0.5,
                            "bubble text should use a readable deep berry tone")
                    }
                }
            }
        }
        content.updatePetHeight(208)
        content.showBubble(PetDialogue.pride.text)
        let longWidth = content.subviews.compactMap { $0 as? NSTextField }.first!.frame.width
        content.showBubble(PetDialogue.entrance.text)
        let shortWidth = content.subviews.compactMap { $0 as? NSTextField }.first!.frame.width
        expect(shortWidth < longWidth, "short dialogue retained an unnecessarily wide bubble")
        let stableBubble = content.subviews.compactMap { $0 as? PetSpeechBubble }.first!
        let stableRect = stableBubble.frame
        for motion in ["idle", "working", "wave", "waiting", "celebrate"] {
            content.spriteView.playMotion(motion)
            expect(stableBubble.frame == stableRect, "bubble jumped when changing \(motion)")
        }
        content.spriteView.playMotion("idle")
        for atlas in [highResolution, fallback] {
            for height in [176.0, 208, 256, 320] {
                let legacy = PetContentView(atlas: atlas, petHeight: height, useLivelyArtwork: false)
                legacy.showBubble(PetDialogue.pride.text)
                let field = legacy.subviews.compactMap { $0 as? PetSpeechBubble }.first!
                let top = legacy.spriteView.frame.minY + height * 29 / 208
                let tip = field.frame.minY + field.tailTipY
                expect((7.5...8.5).contains(top - tip), "\(atlas.pixelScale)x fallback bubble lost head clearance")
                expect(legacy.bounds.contains(field.frame), "fallback bubble clipped at \(height) pt")
            }
        }
        func luminance(_ color: NSColor) -> CGFloat {
            let c = color.usingColorSpace(.sRGB)!
            let channels = [c.redComponent, c.greenComponent, c.blueComponent].map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        for surface in [PetBubbleTheme.surfacePink, PetBubbleTheme.surfaceIce] {
            let contrast = (luminance(surface) + 0.05) / (luminance(PetBubbleTheme.ink) + 0.05)
            expect(contrast >= 7 && surface.alphaComponent == 1,
                "bubble must remain readable even over a busy/dark desktop")
        }
        for text in ["本地测试：正在工作……", "本地测试：完成！", "右键点我可以打开设置哦～"] {
            content.showBubble(text)
            let field = content.subviews.compactMap { $0 as? PetSpeechBubble }.first!
            expect(field.textRect.height <= 36, "diagnostic bubble exceeded two lines")
        }

        if let previewPath = ProcessInfo.processInfo.environment["SNOWFLUFF_DIALOGUE_PREVIEW"] {
            for height in [176.0, 208, 256, 320] {
                for dark in [false, true] {
                    content.updatePetHeight(height)
                    content.showBubble(PetDialogue.pride.text, duration: 8)
                    content.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1)
                        : NSColor(calibratedWhite: 0.98, alpha: 1)).cgColor
                    guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                        expect(false, "could not render dialogue preview"); return
                    }
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        expect(false, "could not encode dialogue preview"); return
                    }
                    let base = URL(fileURLWithPath: previewPath).deletingPathExtension().path
                    let url = URL(fileURLWithPath: "\(base)-\(Int(height))-\(dark ? "dark" : "light").png")
                    try data.write(to: url)
                }
            }
        }


        for scale in [1.0, 2.0] {
            let aligned = PetWindowLayout.make(petHeight: 176, containerWidth: 280, bubbleHeight: 48, spacing: 10)
                .petRect.pixelAligned(backingScale: scale)
            for edge in [aligned.minX, aligned.maxX, aligned.minY, aligned.maxY] {
                expect(abs(edge * scale - (edge * scale).rounded()) < 0.000_001, "destination edge missed a device pixel at \(scale)x")
            }
        }
    }
}

private var checks = RenderingChecks()
do {
    try checks.run()
} catch {
    checks.expect(false, "unexpected error: \(error)")
}

if checks.failures.isEmpty {
    print("PASS: AppKit rendering contract suite")
    exit(0)
}
for failure in checks.failures { fputs("FAIL: \(failure)\n", stderr) }
exit(1)
