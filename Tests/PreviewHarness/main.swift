@preconcurrency import AppKit
import QuartzCore
import Foundation

let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let atlas=try SpriteAtlas(url:URL(fileURLWithPath:CommandLine.arguments[1]))
let output=URL(fileURLWithPath:ProcessInfo.processInfo.environment["SNOWFLUFF_MOTION_DIR"]!).appendingPathComponent("qa/preview-frames")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let old=SpriteView(atlas:atlas,useLivelyArtwork:false),new=SpriteView(atlas:atlas)
let container=NSView(frame:NSRect(x:0,y:0,width:424,height:228))
container.wantsLayer=true
let lightBackground=ProcessInfo.processInfo.environment["SNOWFLUFF_PREVIEW_LIGHT"] == "1"
container.layer?.backgroundColor=(lightBackground ? NSColor(calibratedWhite:0.94,alpha:1) :
    NSColor(calibratedRed:0.07,green:0.10,blue:0.15,alpha:1)).cgColor
for (index,view) in [old,new].enumerated(){view.frame=NSRect(x:CGFloat(index)*212+10,y:10,width:192,height:208);container.addSubview(view)}
let panel=NSPanel(contentRect:container.frame,styleMask:.borderless,backing:.buffered,defer:false)
panel.contentView=container;panel.orderFrontRegardless()
container.layoutSubtreeIfNeeded()
func pump(_ seconds:Double){let end=Date().addingTimeInterval(max(0,seconds));while Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.003))}}
func capture(_ index:Int){
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:848,pixelsHigh:456,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let ctx=NSGraphicsContext(bitmapImageRep:rep)?.cgContext else{fatalError("context")}
    ctx.scaleBy(x:2,y:2)
    (container.layer?.presentation() ?? container.layer)?.render(in:ctx)
    try! rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(String(format:"%04d.png",index)))
}
// Deterministic scripted inputs to the real view/compositor. No desktop recording.
let names=["idle","hover","drag","flight","working","waiting","failed","celebrate"]
let rows=[0,0,0,1,7,6,5,8],counts=[6,6,6,8,6,6,8,6]
var index=0
for (segment,name) in names.enumerated(){
    let start=CACurrentMediaTime()
    // Start the idle/work samples shortly before their short smile cue; the
    // motions run at normal speed. This is an isolated action sample, not a
    // claim that spontaneous cues occur every three seconds on the desktop.
    let cueOffset = segment == 0 ? 9.0 : name == "working" ? 9.0/0.65 : 0
    new.clearGaze();old.clearGaze();new.playMotion(segment<4 ? "idle":name,at:start-cueOffset)
    for frame in 0..<90 {
        let t=Double(frame)/30
        let now=CACurrentMediaTime()
        old.setFrame(row:rows[segment],column:(Int(t*(segment==3 ? 4:8)))%counts[segment])
        new.updateMotion(at:now)
        if name=="hover" {
            old.isHovering=true;new.isHovering=true
            let target=panel.convertPoint(toScreen:NSPoint(x:new.frame.minX+150,y:120))
            new.look(at:target)
            old.setFrame(row:0,column:0)
        }
        if name=="drag" && frame==15 {new.settleAfterDrag()}
        if name=="flight" { new.setFlightPose(progress:t/3,right:true,bank:sin(t*2)*0.045) }
        pump(max(0,start+Double(frame+1)/30-CACurrentMediaTime()))
        capture(index);index+=1
    }
}
panel.orderOut(nil)
print("PASS: \(index) comparison frames, left=previous artwork/cadence, right=new compositor; 30 fps, 8 segments x3 s")
