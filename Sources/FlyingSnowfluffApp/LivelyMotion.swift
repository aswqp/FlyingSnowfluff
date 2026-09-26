@preconcurrency import AppKit
import QuartzCore
import ImageIO
import FlyingSnowfluffCore

struct MotionClip: Decodable {
    let frames: [String]
    let durations: [Double]
    let loop: Bool
    let anchor: [Double]
    let interruptAfter: Double
    var duration: Double { durations.reduce(0, +) }

    func frame(at elapsed: Double) -> String {
        var time = max(0, elapsed)
        if loop { time.formTruncatingRemainder(dividingBy: duration) }
        for (index, hold) in durations.enumerated() {
            if time < hold { return frames[index] }
            time -= hold
        }
        return frames.last!
    }
}

final class MotionLibrary {
    struct RigGeometry: Decodable {
        let scale: Double
        let offsetX: Double
        let offsetY: Double
    }
    private struct Manifest: Decodable {
        let version: Int
        let width: Int
        let height: Int
        let clips: [String: MotionClip]
        let rig: RigGeometry
    }
    struct Bitmap {
        let image: CGImage
        let alpha: [UInt8]
        func isOpaque(_ point: CGPoint, in size: CGSize) -> Bool {
            guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return false }
            let x = Int(point.x / size.width * 384), y = Int(point.y / size.height * 416)
            return alpha[y * 384 + x] > 28
        }
    }
    let directory: URL
    let clips: [String: MotionClip]
    let rig: RigGeometry
    private(set) var speechTopFraction: CGFloat = 1
    private var cache: [String: Bitmap] = [:]
    private var recent: [String] = []

    init(directory: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("motion.json")))
        guard manifest.version == 1, manifest.width == 384, manifest.height == 416 else { throw Failure.invalid }
        self.directory = directory
        clips = manifest.clips
        rig = manifest.rig
        guard rig.scale.isFinite, (0.5...1).contains(rig.scale),
              rig.offsetX.isFinite, (0...192).contains(rig.offsetX),
              rig.offsetY.isFinite, (0...208).contains(rig.offsetY) else { throw Failure.invalid }
        let required = ["idle", "lookLeft", "lookRight", "flyRight", "flyLeft", "wave", "shy", "tilt", "adjustVisor", "nap", "sway", "peek", "working", "waiting", "failed", "celebrate", "focused"]
        guard required.allSatisfy({ clips[$0] != nil }) else { throw Failure.invalid }
        for clip in clips.values {
            guard !clip.frames.isEmpty, clip.frames.count == clip.durations.count,
                  clip.durations.allSatisfy({ $0.isFinite && $0 > 0 }), clip.duration.isFinite,
                  clip.anchor.count == 2, clip.anchor.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  clip.interruptAfter.isFinite, clip.interruptAfter >= 0 else { throw Failure.invalid }
            for name in clip.frames {
                guard Self.safeName(name), let bitmap = bitmap(name),
                      let lastVisible = bitmap.alpha.lastIndex(where: { $0 > 28 }) else { throw Failure.invalid }
                // One stable envelope for all poses: a bubble must not bounce
                // with blinking, gaze changes, breathing or frame changes.
                // This CGContext's alpha rows are bottom-up; artwork is top-down.
                speechTopFraction = min(speechTopFraction, CGFloat(415 - lastVisible / 384) / 416)
            }
        }
        for part in ["body", "wingLeft", "wingRight", "hairLeft", "hairRight"] {
            guard bitmap("neutral-" + part) != nil else { throw Failure.invalid }
        }
        cache.removeAll(); recent.removeAll()
    }

    static func installed() -> MotionLibrary? {
        #if FLYING_SNOWFLUFF_QA
        if let override = ProcessInfo.processInfo.environment["SNOWFLUFF_MOTION_DIR"] {
            return try? MotionLibrary(directory: URL(fileURLWithPath: override))
        }
        #endif
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Lively") else { return nil }
        return try? MotionLibrary(directory: url)
    }

    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.count < 60 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    func bitmap(_ name: String) -> Bitmap? {
        if let cached = cache[name] { return cached }
        guard Self.safeName(name), let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 384, image.height == 416 else { return nil }
        var rgba = [UInt8](repeating: 0, count: 384 * 416 * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let success = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 384, height: 416, bitsPerComponent: 8,
                bytesPerRow: 384 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.translateBy(x: 0, y: 416); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 384, height: 416))
            return true
        }
        guard success else { return nil }
        let bitmap = Bitmap(image: image, alpha: stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
        if recent.count >= 12 { cache.removeValue(forKey: recent.removeFirst()) }
        recent.append(name); cache[name] = bitmap
        return bitmap
    }
    enum Failure: Error { case invalid }
}

// All geometry uses the same normalized sprite rectangle as hit testing.
final class LivelyRenderer {
    private let library: MotionLibrary
    private let root = CALayer()
    private let face = CAShapeLayer()
    private var parts: [(layer: CALayer, bitmap: MotionLibrary.Bitmap)] = []
    private(set) var frameID = ""
    private var size = CGSize.zero
    private var animated = false
    private var poseLayer = CALayer()
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    private var lastExpression: Expression?
    private var lastGaze: CGFloat?
    private var lastBankAngle = 0.0

    init(library: MotionLibrary, parent: CALayer) {
        self.library = library
        root.isGeometryFlipped = true
        parent.addSublayer(root)
        root.addSublayer(poseLayer)
        face.fillColor = NSColor(calibratedRed: 0.08, green: 0.095, blue: 0.20, alpha: 1).cgColor
        face.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
        for (index, eye) in eyes.enumerated() {
            let color = index == 0 ? NSColor.cyan : NSColor(calibratedRed: 0.96,green:0.22,blue:0.89,alpha:1)
            eye.strokeColor = color.cgColor
            eye.fillColor = color.cgColor
            eye.lineCap = .square
            face.addSublayer(eye)
        }
        face.zPosition = 10
        poseLayer.addSublayer(face)
    }

    func resize(_ size: CGSize) {
        guard size != self.size else { return }
        self.size = size
        lastExpression = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        poseLayer.frame = root.bounds
        for (layer, _) in parts { place(layer) }
        CATransaction.commit()
    }

    private func place(_ part: CALayer) {
        part.bounds = CGRect(origin: .zero, size: size)
        part.position = CGPoint(x: size.width * part.anchorPoint.x, y: size.height * part.anchorPoint.y)
        part.contentsGravity = .resize
        part.magnificationFilter = .nearest
        part.minificationFilter = .nearest
    }

    func show(_ id: String, animate: Bool) {
        if frameID == id, animated == animate { return }
        frameID = id; animated = animate
        lastExpression = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        parts.forEach { $0.layer.removeFromSuperlayer() }; parts.removeAll()
        poseLayer.removeAllAnimations()
        poseLayer.transform = CATransform3DIdentity
        lastBankAngle = 0
        let names = id == "neutral" ? ["body", "wingLeft", "wingRight", "hairLeft", "hairRight"] : [id]
        for name in names {
            let bitmapName = id == "neutral" ? "neutral-" + name : name
            guard let bitmap = library.bitmap(bitmapName) else { continue }
            let part = CALayer()
            switch name {
            case "wingLeft": part.anchorPoint = CGPoint(x: 124.0/384, y: 298.0/416)
            case "wingRight": part.anchorPoint = CGPoint(x: 260.0/384, y: 298.0/416)
            case "hairLeft": part.anchorPoint = CGPoint(x: 126.0/384, y: 243.0/416)
            case "hairRight": part.anchorPoint = CGPoint(x: 258.0/384, y: 243.0/416)
            default: part.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            }
            // Anchors are authored against the unscaled drawing and follow the
            // same calibrated content transform as the extracted layers.
            part.anchorPoint = CGPoint(x:(part.anchorPoint.x*384*library.rig.scale+library.rig.offsetX)/384,
                y:(part.anchorPoint.y*416*library.rig.scale+library.rig.offsetY)/416)
            place(part); part.contents = bitmap.image
            poseLayer.addSublayer(part); parts.append((part, bitmap))
            if animate && id == "neutral" && name != "body" {
                let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                let amount = name.hasPrefix("wing") ? 0.018 : 0.012
                sway.values = [0, amount, 0, -amount, 0]
                sway.duration = name.hasSuffix("Left") ? 3.8 : 4.7
                sway.repeatCount = .infinity; sway.beginTime = CACurrentMediaTime() + (name.hasSuffix("Left") ? 0 : 0.4)
                part.add(sway, forKey: "sway")
            }
        }
        // Keep overlay last as well as front-most: offscreen CALayer rendering
        // does not honor every compositor z-order operation.
        face.removeFromSuperlayer(); poseLayer.addSublayer(face)
        face.isHidden = id != "neutral"
        if animate {
            let breath = CAKeyframeAnimation(keyPath: "transform.translation.y")
            breath.values = [0, -size.height/208, 0, size.height/416, 0]
            breath.duration = 4.2; breath.repeatCount = .infinity
            poseLayer.add(breath, forKey: "breath")
        }
        CATransaction.commit()
        expression(.neutral, gaze: 0)
    }

    enum Expression: CaseIterable { case neutral, smile, blink, shy, sleepy, focused, curious, failed }
    func expression(_ expression: Expression, gaze: CGFloat) {
        guard frameID == "neutral" else { return }
        // A hidden/unchanged visor must not rebuild vector paths every 125 ms.
        // Quantize the sub-pixel eye lead; head turns retain their drawn poses.
        let gaze=(gaze*4).rounded()/4
        guard lastExpression != expression || lastGaze != gaze else { return }
        lastExpression=expression;lastGaze=gaze
        let sx=size.width/384,sy=size.height/416
        var registration=CGAffineTransform(a:library.rig.scale,b:0,c:0,d:library.rig.scale,
            tx:library.rig.offsetX*sx,ty:library.rig.offsetY*sy)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        face.isHidden = expression == .neutral && abs(gaze) < 0.01
        face.frame = root.bounds
        let lenses=CGMutablePath()
        lenses.addRect(CGRect(x:144*sx,y:194*sy,width:38*sx,height:34*sy))
        lenses.addRect(CGRect(x:209*sx,y:194*sy,width:33*sx,height:34*sy))
        face.path = lenses.copy(using:&registration)
        for (index,x) in [161.0,222.0].enumerated() {
            let p=CGMutablePath()
            let cx=(x+Double(gaze)*3)*sx, cy=210*sy
            switch expression {
            case .neutral:
                for dx in [-5.0,5.0] { p.addRect(CGRect(x:cx+dx*sx-1.5*sx,y:cy-9*sy,width:3*sx,height:18*sy)) }
            case .blink: p.addRect(CGRect(x:cx-8*sx,y:cy,width:16*sx,height:2*sy))
            case .sleepy: p.addRect(CGRect(x:cx-6*sx,y:cy+3*sy,width:12*sx,height:3*sy))
            case .focused: p.move(to:CGPoint(x:cx-7*sx,y:cy-2*sy));p.addLine(to:CGPoint(x:cx+7*sx,y:cy+1*sy))
            case .smile,.shy:
                p.move(to:CGPoint(x:cx-8*sx,y:cy+3*sy));p.addLine(to:CGPoint(x:cx-4*sx,y:cy-3*sy));p.addLine(to:CGPoint(x:cx+4*sx,y:cy-3*sy));p.addLine(to:CGPoint(x:cx+8*sx,y:cy+3*sy))
                if expression == .shy { p.move(to:CGPoint(x:cx-6*sx,y:cy+7*sy));p.addLine(to:CGPoint(x:cx+6*sx,y:cy+7*sy)) }
            case .curious: p.addRect(CGRect(x:cx-2*sx,y:cy-(x<180 ? 9:4)*sy,width:4*sx,height:(x<180 ? 18:8)*sy))
            case .failed:
                p.move(to:CGPoint(x:cx-6*sx,y:cy-6*sy));p.addLine(to:CGPoint(x:cx+6*sx,y:cy+6*sy))
                p.move(to:CGPoint(x:cx+6*sx,y:cy-6*sy));p.addLine(to:CGPoint(x:cx-6*sx,y:cy+6*sy))
            }
            let eye=eyes[index]
            eye.frame=root.bounds
            eye.path=p.copy(using:&registration);eye.lineWidth=max(1,2*sx*library.rig.scale)
            eye.fillColor = [Expression.smile,.shy,.focused,.failed].contains(expression) ? nil : eye.strokeColor
        }
        CATransaction.commit()
    }

    func settle() {
        guard animated else { return }
        for (part,_) in parts {
            let spring=CASpringAnimation(keyPath:"transform.translation.y")
            spring.fromValue = -min(4,size.height/104);spring.toValue=0
            spring.mass=1;spring.stiffness=170;spring.damping=16;spring.duration=min(1,spring.settlingDuration)
            part.add(spring,forKey:"settle")
        }
    }

    func bank(_ radians: Double) {
        let angle = FlightMotion.quantizedBankAngle(radians)
        guard angle != lastBankAngle else { return }
        lastBankAngle = angle
        CATransaction.begin(); CATransaction.setDisableActions(true)
        poseLayer.transform = CATransform3DMakeRotation(angle,0,0,1)
        CATransaction.commit()
    }

    func isOpaque(_ point: CGPoint) -> Bool {
        for (part,bitmap) in parts {
            let presentation=part.presentation() ?? part
            let local=presentation.convert(point,from:root.presentation() ?? root)
            if bitmap.isOpaque(local,in:size) { return true }
        }
        return false
    }
}
