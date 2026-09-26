@preconcurrency import AppKit
import QuartzCore
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let base = URL(fileURLWithPath:CommandLine.arguments[1])
let atlas = try SpriteAtlas(url:base)
guard let library = MotionLibrary.installed() else { fatalError("motion library failed to load") }
let output = library.directory.appendingPathComponent("qa/runtime")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let view=SpriteView(atlas:atlas)
view.frame=NSRect(x:0,y:0,width:384,height:416)
let panel=NSPanel(contentRect:view.frame,styleMask:.borderless,backing:.buffered,defer:false)
panel.contentView=view;panel.isOpaque=false;panel.backgroundColor = .clear
panel.setFrameOrigin(NSPoint(x:100,y:100));panel.orderFrontRegardless()
var failures=[String]()
func expect(_ truth:Bool,_ message:String){if !truth{failures.append(message)}}
func pump(_ seconds:Double){
    let end=Date().addingTimeInterval(seconds)
    while Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
}
func capture(_ name:String){
    pump(0.05)
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(view.bounds.width*2),pixelsHigh:Int(view.bounds.height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
        let context=NSGraphicsContext(bitmapImageRep:rep)?.cgContext else { failures.append("capture unavailable");return }
    context.scaleBy(x:2,y:2)
    context.translateBy(x:0,y:view.bounds.height);context.scaleBy(x:1,y:-1)
    view.layer?.render(in:context)
    guard let data=rep.representation(using:.png,properties:[:]) else { failures.append("PNG unavailable");return }
    try! data.write(to:output.appendingPathComponent(name+".png"))
}
expect(view.hasLivelyArtwork,"new renderer did not load")
expect(library.clips["idle"]!.frame(at:10000)=="neutral","idle time lookup failed")
expect(library.clips["wave"]!.frame(at:999)=="neutral","one-shot clip did not finish")
expect(library.bitmap("../escape")==nil,"unsafe bitmap name accepted")
for (index,height) in [176.0,208,256,320].enumerated(){
    view.frame.size=NSSize(width:height*192/208,height:height)
    panel.setContentSize(view.frame.size);view.layoutSubtreeIfNeeded()
    view.playMotion("idle");capture("size-\(index)")
    let opaque=panel.convertPoint(toScreen:NSPoint(x:view.bounds.midX,y:view.bounds.midY))
    expect(view.containsOpaquePixel(screenPoint:opaque),"center alpha hit failed at \(height)")
    let clear=panel.convertPoint(toScreen:NSPoint(x:1,y:1))
    expect(!view.containsOpaquePixel(screenPoint:clear),"transparent corner hit at \(height)")
}
view.frame.size=NSSize(width:192,height:208);panel.setContentSize(view.frame.size);view.layoutSubtreeIfNeeded()
for (index,expression) in LivelyRenderer.Expression.allCases.enumerated(){
    view.playMotion("idle");view.qaExpression(expression);capture("expression-\(index)")
}
let expressions = try (0..<8).map { try Data(contentsOf:output.appendingPathComponent("expression-\($0).png")) }
expect(Set(expressions).count == 8,"eight expressions did not produce eight distinct rendered images")
view.playMotion("idle");capture("hover-before")
view.qaExpression(.neutral,gaze:0.4);capture("hover-after")
let before=NSBitmapImageRep(data:try Data(contentsOf:output.appendingPathComponent("hover-before.png")))!
let after=NSBitmapImageRep(data:try Data(contentsOf:output.appendingPathComponent("hover-after.png")))!
// Derived from the actual approved neutral PNG's visor, independent of the
// renderer's registration transform. Catches the reported extra forehead visor.
let lensBounds=CGRect(x:147,y:220,width:96,height:38)
var changed=0,escaped=0
for y in 0..<before.pixelsHigh { for x in 0..<before.pixelsWide {
    if before.colorAt(x:x,y:y) != after.colorAt(x:x,y:y) {
        changed += 1
        if !lensBounds.contains(CGPoint(x:x,y:y)) { escaped += 1 }
    }
}}
expect(changed>0,"hover has no visible eye response")
expect(escaped==0,"hover painted \(escaped) pixels outside the original visor (forehead duplicate regression)")
for name in ["idle","lookLeft","lookRight","wave","shy","tilt","adjustVisor","nap","sway","peek","working","waiting","failed","celebrate"]{
    let start=CACurrentMediaTime();view.playMotion(name,at:start);view.updateMotion(at:start+0.5);capture(name)
}
view.animationsEnabled=false;view.playMotion("idle")
expect(view.qaMotionFrame=="neutral","paused renderer is not static")
view.animationsEnabled=true
let cueStart=CACurrentMediaTime()
view.playMotion("idle",at:cueStart);view.updateMotion(at:cueStart+24.3)
expect(view.qaMotionFrame=="gaze-left","idle micro look did not play")
view.quietCompanionship=true;view.updateMotion(at:cueStart+24.3)
expect(view.qaMotionFrame=="neutral","quiet mode failed to suppress automatic micro look")
view.quietCompanionship=false
view.playMotion("working",at:cueStart);view.updateMotion(at:cueStart+24.3/0.65)
expect(view.qaMotionFrame=="gaze-left","working companion did not play slower micro look")
view.playMotion("working",at:cueStart+5)
view.updateMotion(at:cueStart+24.3/0.65)
expect(view.qaMotionFrame=="gaze-left","frequent working/tool hooks reset the micro-reaction clock")
view.reduceMotion=true;view.updateMotion(at:cueStart+24.3/0.65)
expect(view.qaMotionFrame=="neutral","reduced working pose was not static")
panel.orderOut(nil)
if failures.isEmpty{print("PASS: lively assets, timing, 4 sizes, alpha hit testing, 8 expressions; runtime PNGs at \(output.path)")}
else{failures.forEach{fputs("FAIL: \($0)\n",stderr)}}
exit(failures.isEmpty ? 0 : 1)
