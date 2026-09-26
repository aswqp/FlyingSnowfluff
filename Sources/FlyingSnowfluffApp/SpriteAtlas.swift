@preconcurrency import AppKit
import CoreGraphics
import FlyingSnowfluffCore
import ImageIO

final class SpriteAtlas {
    struct Metrics: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        let columns: Int
        let rows: Int

        var cellPixelWidth: Int { pixelWidth / columns }
        var cellPixelHeight: Int { pixelHeight / rows }
    }

    static let columns = 8
    static let rows = 9
    static let logicalCellWidth = 192
    static let logicalCellHeight = 208

    let metrics: Metrics
    let pixelScale: Int
    let usesSplitFrames: Bool
    private var image: CGImage?
    private let atlasURL: URL
    private let frameDirectory: URL?
    private var cachedRow: Int?
    private var frameCache: [Int: CGImage] = [:]
    private let alphaMask: [UInt8]
    lazy var speechTopFraction: CGFloat = {
        let width = Self.columns * Self.logicalCellWidth
        for y in 0..<Self.logicalCellHeight {
            for row in 0..<Self.rows {
                let start = (row * Self.logicalCellHeight + Self.logicalCellHeight - 1 - y) * width
                if alphaMask[start..<(start + width)].contains(where: { $0 > 28 }) {
                    return CGFloat(y) / CGFloat(Self.logicalCellHeight)
                }
            }
        }
        return 0
    }()

    init(url: URL, alphaMaskURL: URL? = nil) throws {
        atlasURL = url
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { throw AtlasError.invalidImage }

        let metrics = Metrics(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            columns: Self.columns,
            rows: Self.rows
        )
        guard metrics.pixelWidth % Self.columns == 0,
              metrics.pixelHeight % Self.rows == 0,
              metrics.cellPixelWidth % Self.logicalCellWidth == 0,
              metrics.cellPixelHeight % Self.logicalCellHeight == 0
        else { throw AtlasError.invalidImage }

        let widthScale = metrics.cellPixelWidth / Self.logicalCellWidth
        let heightScale = metrics.cellPixelHeight / Self.logicalCellHeight
        guard widthScale == heightScale, (1...2).contains(widthScale) else {
            throw AtlasError.invalidImage
        }

        self.metrics = metrics
        pixelScale = widthScale
        frameDirectory = Self.compatibleFrameDirectory(for: url, metrics: metrics, pixelScale: widthScale)
        usesSplitFrames = frameDirectory != nil
        if frameDirectory == nil {
            guard let decodedImage = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions) else {
                throw AtlasError.invalidImage
            }
            image = decodedImage
        } else {
            image = nil
        }
        guard let maskImage = Self.compatibleMaskImage(at: alphaMaskURL, options: sourceOptions)
            ?? image
            ?? CGImageSourceCreateImageAtIndex(source, 0, sourceOptions)
        else { throw AtlasError.invalidImage }
        let maskWidth = Self.columns * Self.logicalCellWidth
        let maskHeight = Self.rows * Self.logicalCellHeight
        var rgba = [UInt8](repeating: 0, count: maskWidth * maskHeight * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: maskWidth,
                height: maskHeight,
                bitsPerComponent: 8,
                bytesPerRow: maskWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.translateBy(x: 0, y: CGFloat(maskHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                maskImage,
                in: CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight)
            )
            return true
        }
        guard rendered else { throw AtlasError.invalidImage }
        var alpha = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        for index in alpha.indices { alpha[index] = rgba[index * 4 + 3] }
        alphaMask = alpha
    }

    static func loadBest(candidates: [URL]) throws -> SpriteAtlas {
        let maskCandidate = candidates.last
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let separateMask = maskCandidate == url ? nil : maskCandidate
            if let atlas = try? SpriteAtlas(url: url, alphaMaskURL: separateMask) { return atlas }
        }
        throw AtlasError.invalidImage
    }

    private static func compatibleMaskImage(at url: URL?, options: CFDictionary) -> CGImage? {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == columns * logicalCellWidth,
              image.height == rows * logicalCellHeight
        else { return nil }
        return image
    }

    private static func compatibleFrameDirectory(for atlasURL: URL, metrics: Metrics, pixelScale: Int) -> URL? {
        let directoryName = pixelScale == 2 ? "frames@2x" : "frames@1x"
        let directory = atlasURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              (0..<rows).allSatisfy({ row in
                  (0..<columns).allSatisfy { frameAt(row: row, column: $0, in: directory, matches: metrics) }
              })
        else { return nil }
        return directory
    }

    private static func frameAt(row: Int, column: Int, in directory: URL, matches metrics: Metrics) -> Bool {
        let url = directory.appendingPathComponent("r\(row)-c\(column).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == metrics.cellPixelWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == metrics.cellPixelHeight
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    func frame(row: Int, column: Int) -> CGImage? {
        guard (0..<metrics.rows).contains(row), (0..<metrics.columns).contains(column) else {
            return nil
        }
        if let frameDirectory {
            if cachedRow != row {
                cachedRow = row
                frameCache.removeAll(keepingCapacity: true)
            }
            if let cached = frameCache[column] { return cached }
            let url = frameDirectory.appendingPathComponent("r\(row)-c\(column).png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let frameImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  frameImage.width == metrics.cellPixelWidth,
                  frameImage.height == metrics.cellPixelHeight
            else { return fallbackFrame(row: row, column: column) }
            frameCache[column] = frameImage
            return frameImage
        }
        return fallbackFrame(row: row, column: column)
    }

    private func fallbackFrame(row: Int, column: Int) -> CGImage? {
        if image == nil, let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil) {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return image?.cropping(to: CGRect(
            x: column * metrics.cellPixelWidth,
            y: row * metrics.cellPixelHeight,
            width: metrics.cellPixelWidth,
            height: metrics.cellPixelHeight
        ))
    }

    func isOpaque(row: Int, column: Int, normalizedX: CGFloat, normalizedY: CGFloat) -> Bool {
        guard (0..<metrics.rows).contains(row), (0..<metrics.columns).contains(column),
              normalizedX >= 0, normalizedX < 1, normalizedY >= 0, normalizedY < 1
        else { return false }
        let localX = min(Self.logicalCellWidth - 1, max(0, Int(normalizedX * CGFloat(Self.logicalCellWidth))))
        let localY = min(Self.logicalCellHeight - 1, max(0, Int(normalizedY * CGFloat(Self.logicalCellHeight))))
        let maskWidth = Self.columns * Self.logicalCellWidth
        let x = column * Self.logicalCellWidth + localX
        let y = row * Self.logicalCellHeight + localY
        return alphaMask[y * maskWidth + x] > 28
    }

    enum AtlasError: Error { case invalidImage }
}

final class PetContentView: NSView {
    let spriteView: SpriteView
    private let bubble = PetSpeechBubble()
    private var bubbleHideWorkItem: DispatchWorkItem?
    private var petHeight: CGFloat

    override var isFlipped: Bool { true }

    init(atlas: SpriteAtlas, petHeight: CGFloat, useLivelyArtwork: Bool = true) {
        self.petHeight = petHeight
        spriteView = SpriteView(atlas: atlas, useLivelyArtwork: useLivelyArtwork)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(spriteView)

        bubble.isHidden = true
        addSubview(bubble)
        updatePetHeight(petHeight)
    }

    required init?(coder: NSCoder) { nil }

    func updatePetHeight(_ petHeight: CGFloat) {
        self.petHeight = petHeight
        let layout = PetWindowLayout.make(
            petHeight: petHeight,
            containerWidth: 280,
            bubbleHeight: 48,
            spacing: 10
        )
        frame.size = NSSize(width: layout.windowSize.width, height: layout.windowSize.height)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let alignedPetRect = layout.petRect.pixelAligned(backingScale: scale)
        spriteView.frame = NSRect(
            x: alignedPetRect.x,
            y: alignedPetRect.y,
            width: alignedPetRect.width,
            height: alignedPetRect.height
        )
        layoutBubble(backingScale: scale)
    }

    private func layoutBubble(backingScale: CGFloat? = nil) {
        let scale = backingScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = bubble.fittedSize(maxWidth: bounds.width - 16)
        let headTop = spriteView.frame.minY + spriteView.speechTopInset
        // Keep the original window/sprite geometry (and flight/hit testing),
        // placing the bubble in the artwork's existing transparent headroom.
        let y = max(0, headTop - PetSpeechBubble.headClearance - size.height + PetSpeechBubble.shadowInset)
        bubble.frame = NSRect(x: ((bounds.midX - size.width / 2) * scale).rounded() / scale,
            y: (y * scale).rounded(.down) / scale, width: size.width, height: size.height)
        bubble.needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePetHeight(petHeight)
    }

    func installContextMenu(_ menu: NSMenu, willOpen: @escaping () -> Void = {}) {
        spriteView.menu = menu
        spriteView.onContextMenuRequested = willOpen
    }

    func showBubble(_ text: String, duration: TimeInterval = 3.5) {
        bubbleHideWorkItem?.cancel()
        bubble.stringValue = text
        layoutBubble()
        bubble.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.bubble.isHidden = true }
        bubbleHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

final class SpriteView: NSView {
    private let atlas: SpriteAtlas
    private(set) var row = 0
    private(set) var column = 0
    var reduceMotion = false
    var isHovering = false
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onMovedByDrag: (() -> Void)?
    var onContextMenuRequested: (() -> Void)?

    private var mouseDownLocation = NSPoint.zero
    private var windowOriginAtMouseDown = NSPoint.zero
    private var didDrag = false
    private var gazeOffset: CGFloat?
    private let motionLibrary: MotionLibrary?
    private var livelyRenderer: LivelyRenderer?
    private var motionName = "idle"
    private var motionStarted = CACurrentMediaTime()
    private var gazeStarted = CACurrentMediaTime()
    private var flightFrameID: String?
    private var lastLayoutSize = CGSize.zero
    var animationsEnabled = true
    var quietCompanionship = false
    private(set) var isDragging = false
    var onDragBegan: (() -> Void)?

    override var isFlipped: Bool { true }

    var speechTopInset: CGFloat {
        bounds.height * (motionLibrary?.speechTopFraction ?? atlas.speechTopFraction)
    }

    init(atlas: SpriteAtlas, useLivelyArtwork: Bool = true) {
        self.atlas = atlas
        motionLibrary = useLivelyArtwork ? MotionLibrary.installed() : nil
        super.init(frame: .zero)
        wantsLayer = true
        if let motionLibrary, let layer {
            livelyRenderer = LivelyRenderer(library: motionLibrary, parent: layer)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenuRequested?()
        return super.menu(for: event)
    }

    func setFrame(row: Int, column: Int) {
        self.row = min(8, max(0, row))
        self.column = min(7, max(0, column))
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        livelyRenderer?.resize(bounds.size)
        updateMotion(at: CACurrentMediaTime())
    }

    var hasLivelyArtwork: Bool { livelyRenderer != nil }
    func motionDuration(_ name: String) -> Double? { motionLibrary?.clips[name]?.duration }

    func playMotion(_ name: String, at now: Double = CACurrentMediaTime()) {
        // Tool start/finish events share the working pose. Do not restart the
        // idle-reaction clock on every hook, or a busy Codex never blinks/looks.
        if name == "working", motionName == name, flightFrameID == nil {
            updateMotion(at: now)
            return
        }
        motionName = name; motionStarted = now; flightFrameID = nil
        updateMotion(at: now)
    }

    func setFlightPose(progress: Double, right: Bool, bank: Double = 0) {
        let side = right ? "right" : "left"
        let phase = FlightMotion.phase(progress: progress)
        let pose = phase == .preparing ? "takeoff" : phase == .settling ? "land" : "cruise"
        let id = pose + "-" + side
        if id != flightFrameID {
            flightFrameID = id
            livelyRenderer?.show(id, animate: animationsEnabled && !reduceMotion)
        }
        livelyRenderer?.bank(bank)
    }

    func updateMotion(at now: Double) {
        guard let motionLibrary, let livelyRenderer else { return }
        livelyRenderer.resize(bounds.size)
        var id = motionLibrary.clips[motionName]?.frame(at: animationsEnabled && !reduceMotion ? now-motionStarted : 0) ?? "neutral"
        if let flightFrameID { id = flightFrameID }
        let companionPose = motionName == "idle" || motionName == "working"
        var cue = IdleMicroCue.rest
        if companionPose && animationsEnabled && !reduceMotion && !quietCompanionship && !isDragging && gazeOffset == nil {
            cue = IdleMicroMotion.cue(elapsed:(now-motionStarted) * (motionName == "working" ? 0.65:1))
            switch cue {
            case .front: id = "gaze-front"
            case .lookLeft: id = "gaze-left"
            case .lookRight: id = "gaze-right"
            default: break
            }
        }
        // Gaze is a drawn head turn, not a whole-sprite rotation. Brief eyes-first lead.
        if companionPose, let gazeOffset, now-gazeStarted > 0.16, abs(gazeOffset)>0.5 {
            id = gazeOffset < 0 ? "gaze-left" : "gaze-right"
        }
        livelyRenderer.show(id, animate: animationsEnabled && !reduceMotion)
        if id == "neutral" {
            let phase = (now-motionStarted).truncatingRemainder(dividingBy: 5.7)
            let expression: LivelyRenderer.Expression = cue == .smile ? .smile :
                (cue == .blink || (animationsEnabled && !reduceMotion && phase > 5.48)) ? .blink : .neutral
            livelyRenderer.expression(expression,gaze:gazeOffset ?? 0)
        }
    }

    func settleAfterDrag() { livelyRenderer?.settle() }
    #if FLYING_SNOWFLUFF_QA
    var qaMotionFrame: String? { livelyRenderer?.frameID }
    func qaExpression(_ expression: LivelyRenderer.Expression, gaze: CGFloat = 0) { livelyRenderer?.expression(expression,gaze:gaze) }
    #endif

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if livelyRenderer != nil { return }
        guard let frameImage = atlas.frame(row: row, column: column),
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(frameImage, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
        if let gazeOffset {
            let pixel = max(2, (bounds.height / 80).rounded())
            let gazeCenterX = bounds.midX + gazeOffset * bounds.width * 0.035
            let gazeY = bounds.minY + bounds.height * 0.365
            NSColor.systemCyan.withAlphaComponent(0.92).setFill()
            NSRect(x: gazeCenterX - pixel * 2.8, y: gazeY, width: pixel, height: pixel).fill()
            NSRect(x: gazeCenterX + pixel * 1.8, y: gazeY, width: pixel, height: pixel).fill()
            NSColor.systemPink.withAlphaComponent(0.70).setFill()
            NSRect(x: gazeCenterX - pixel * 1.3, y: gazeY + pixel, width: pixel, height: pixel).fill()
            NSRect(x: gazeCenterX + pixel * 0.3, y: gazeY + pixel, width: pixel, height: pixel).fill()
        }
    }

    func containsOpaquePixel(screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let local = convert(windowPoint, from: nil)
        guard bounds.contains(local), bounds.width > 0, bounds.height > 0 else { return false }
        if let livelyRenderer { return livelyRenderer.isOpaque(local) }
        return atlas.isOpaque(
            row: row,
            column: column,
            normalizedX: local.x / bounds.width,
            normalizedY: local.y / bounds.height
        )
    }

    func look(at screenPoint: NSPoint) {
        guard let window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let local = convert(windowPoint, from: nil)
        let nextOffset = min(1, max(-1, (local.x - bounds.midX) / max(1, bounds.width * 0.22)))
        if gazeOffset != nextOffset {
            if gazeOffset == nil || (gazeOffset! < 0) != (nextOffset < 0) { gazeStarted = CACurrentMediaTime() }
            gazeOffset = nextOffset
            if livelyRenderer != nil { updateMotion(at: CACurrentMediaTime()) } else { needsDisplay = true }
        }
    }

    func clearGaze() {
        guard gazeOffset != nil else { return }
        gazeOffset = nil
        if livelyRenderer != nil { updateMotion(at: CACurrentMediaTime()) } else { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin ?? .zero
        didDrag = false
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - mouseDownLocation.x
        let deltaY = current.y - mouseDownLocation.y
        if abs(deltaX) + abs(deltaY) > 3 && !didDrag {
            didDrag = true; isDragging = true; onDragBegan?()
        }
        window.setFrameOrigin(NSPoint(
            x: windowOriginAtMouseDown.x + deltaX,
            y: windowOriginAtMouseDown.y + deltaY
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            isDragging = false
            onMovedByDrag?()
        } else if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }
}
