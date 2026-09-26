@preconcurrency import AppKit

/// Shared palette: warm snow-white, pink hair, cyan electronics and berry ink.
enum PetBubbleTheme {
    static let surfacePink = NSColor(srgbRed: 1, green: 0.945, blue: 0.973, alpha: 1)
    static let surfaceIce = NSColor(srgbRed: 0.935, green: 0.982, blue: 1, alpha: 1)
    static let borderCyan = NSColor(srgbRed: 0.24, green: 0.75, blue: 0.88, alpha: 1)
    static let borderPink = NSColor(srgbRed: 0.94, green: 0.49, blue: 0.71, alpha: 1)
    static let ink = NSColor(srgbRed: 0.30, green: 0.18, blue: 0.30, alpha: 1)
}

/// A non-interactive, two-line native label; no backdrop blur or animation loop.
final class PetSpeechBubble: NSTextField {
    static let shadowInset: CGFloat = 4
    static let tailHeight: CGFloat = 6
    static let headClearance: CGFloat = 8
    private static let paddingX: CGFloat = 14
    private static let paddingY: CGFloat = 8

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .systemFont(ofSize: 14, weight: .semibold)
        textColor = PetBubbleTheme.ink
        maximumNumberOfLines = 2
        lineBreakMode = .byWordWrapping
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var dialogue: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: stringValue, attributes: [
            .font: font!, .foregroundColor: PetBubbleTheme.ink, .paragraphStyle: paragraph
        ])
    }

    func fittedSize(maxWidth: CGFloat) -> NSSize {
        let horizontalInsets = 2 * (Self.shadowInset + Self.paddingX)
        let lineWidth = stringValue.components(separatedBy: "\n").map {
            NSAttributedString(string: $0, attributes: [.font: font!]).size().width
        }.max() ?? 0
        // CJK fallback glyphs / hanging punctuation need a little more room
        // than NSAttributedString's typographic advance on some macOS locales.
        let width = min(maxWidth, max(132, ceil(lineWidth) + horizontalInsets + 16))
        let measured = dialogue.boundingRect(with: NSSize(width: width - horizontalInsets, height: 1_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = ceil(measured.height) + 2 * (Self.shadowInset + Self.paddingY) + Self.tailHeight
        return NSSize(width: width, height: height)
    }

    var bodyRect: NSRect {
        var rect = bounds.insetBy(dx: Self.shadowInset, dy: Self.shadowInset)
        rect.size.height -= Self.tailHeight
        return rect
    }

    var textRect: NSRect { bodyRect.insetBy(dx: Self.paddingX, dy: Self.paddingY) }
    var tailTipY: CGFloat { bounds.maxY - Self.shadowInset }

    private func outline(in rect: NSRect, tail: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let r = min(14, rect.height / 2), c = r * 0.55228475
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY, mid = rect.midX
        p.move(to: NSPoint(x: x0 + r, y: y0))
        p.line(to: NSPoint(x: x1 - r, y: y0))
        p.curve(to: NSPoint(x: x1, y: y0 + r), controlPoint1: NSPoint(x: x1 - r + c, y: y0), controlPoint2: NSPoint(x: x1, y: y0 + r - c))
        p.line(to: NSPoint(x: x1, y: y1 - r))
        p.curve(to: NSPoint(x: x1 - r, y: y1), controlPoint1: NSPoint(x: x1, y: y1 - r + c), controlPoint2: NSPoint(x: x1 - r + c, y: y1))
        p.line(to: NSPoint(x: mid + 6, y: y1))
        p.line(to: NSPoint(x: mid, y: tail))
        p.line(to: NSPoint(x: mid - 6, y: y1))
        p.line(to: NSPoint(x: x0 + r, y: y1))
        p.curve(to: NSPoint(x: x0, y: y1 - r), controlPoint1: NSPoint(x: x0 + r - c, y: y1), controlPoint2: NSPoint(x: x0, y: y1 - r + c))
        p.line(to: NSPoint(x: x0, y: y0 + r))
        p.curve(to: NSPoint(x: x0 + r, y: y0), controlPoint1: NSPoint(x: x0, y: y0 + r - c), controlPoint2: NSPoint(x: x0 + r - c, y: y0))
        p.close()
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = outline(in: bodyRect, tail: tailTipY)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = PetBubbleTheme.ink.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        PetBubbleTheme.surfacePink.setFill()
        outer.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: PetBubbleTheme.borderCyan, ending: PetBubbleTheme.borderPink)?.draw(in: outer, angle: 0)
        let inner = outline(in: bodyRect.insetBy(dx: 1.1, dy: 1.1), tail: tailTipY - 1.5)
        NSGradient(starting: PetBubbleTheme.surfacePink, ending: PetBubbleTheme.surfaceIce)?.draw(in: inner, angle: 0)
        NSGraphicsContext.saveGraphicsState()
        textRect.clip()
        dialogue.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }
}
