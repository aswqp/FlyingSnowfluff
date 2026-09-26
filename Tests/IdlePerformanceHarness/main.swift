@preconcurrency import AppKit
import Foundation
import Darwin
import FlyingSnowfluffCore

guard CommandLine.arguments.count == 3 else {
    fputs("FAIL: provide both 2x atlas and 1x alpha-mask atlas, matching the installed App\n", stderr)
    exit(2)
}

let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let suite="snowfluff.idle.qa.\(UUID().uuidString)"
let defaults=UserDefaults(suiteName:suite)!
var settings=PetSettings.default;settings.launchAtLogin=false
PetSettingsStore.save(settings,to:defaults)
let atlas=try SpriteAtlas.loadBest(candidates:CommandLine.arguments.dropFirst().map{URL(fileURLWithPath:$0)})
let controller=PetController(atlas:atlas,defaults:defaults)
controller.start()
controller.setQuietCompanionship(false) // Measure the default micro reactions, not a simplified quiet mode.
var first=rusage()
getrusage(RUSAGE_SELF,&first)
let start=ProcessInfo.processInfo.systemUptime
DispatchQueue.main.asyncAfter(deadline:.now()+120){
    var last=rusage();getrusage(RUSAGE_SELF,&last)
    func cpu(_ u:rusage)->Double{Double(u.ru_utime.tv_sec+u.ru_stime.tv_sec)+Double(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6}
    let percent=(cpu(last)-cpu(first))/(ProcessInfo.processInfo.systemUptime-start)*100
    let rss=Double(last.ru_maxrss)/1048576
    controller.stop();defaults.removePersistentDomain(forName:suite)
    print(String(format:"%@ idle 120 s CPU %.3f%% peak RSS %.2f MiB",percent<1 && rss<100 ? "PASS:" : "FAIL:",percent,rss))
    exit(percent<1 && rss<100 ? 0:1)
}
app.run()
