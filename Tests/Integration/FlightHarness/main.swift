@preconcurrency import AppKit
import Darwin
import Foundation

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("FAIL: expected 2x spritesheet path and optional 1x fallback path\n", stderr)
    exit(2)
}

let atlasURLs = CommandLine.arguments.dropFirst().map(URL.init(fileURLWithPath:))
guard let atlas = try? SpriteAtlas.loadBest(candidates: atlasURLs) else {
    fputs("FAIL: could not load spritesheet\n", stderr)
    exit(2)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = PetController(atlas: atlas)
controller.setCrossDisplays(false)
controller.setReduceMotion(false)
controller.setPaused(false)
controller.start()
let performanceStart = ProcessInfo.processInfo.systemUptime
var startingUsage = rusage()
getrusage(RUSAGE_SELF, &startingUsage)

var samples: [PetController.QASnapshot] = []
var violations: [String] = []
var flightEndUsage: rusage?
var flightElapsed: Double?

func sample() {
    let snapshot = controller.qaSnapshot()
    samples.append(snapshot)
    if !snapshot.isFlying && flightEndUsage == nil && samples.contains(where: \.isFlying) {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        flightEndUsage = usage
        flightElapsed = ProcessInfo.processInfo.systemUptime - performanceStart
    }
    if snapshot.isFlying {
        if !snapshot.ignoresMouseEvents {
            violations.append("flight window intercepted the mouse")
        }
        let frame = snapshot.petFrame
        let visible = snapshot.visibleFrame
        if frame.minX < visible.minX - 0.5 || frame.maxX > visible.maxX + 0.5
            || frame.minY < visible.minY - 0.5 || frame.maxY > visible.maxY + 0.5 {
            violations.append("flight frame left the visible screen: \(frame) vs \(visible)")
        }
        if snapshot.animationRow != 1 && snapshot.animationRow != 2 {
            violations.append("unexpected flight animation row \(snapshot.animationRow)")
        }
    }
}

controller.startFlight(userInitiated: true)
let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in sample() }

DispatchQueue.main.asyncAfter(deadline: .now() + 10.2) {
    timer.invalidate()
    sample()
    controller.stop()

    let flightSamples = samples.filter(\.isFlying)
    let distinctOrigins = Set(flightSamples.map {
        "\(Int($0.petFrame.origin.x.rounded())):\(Int($0.petFrame.origin.y.rounded()))"
    })
    if flightSamples.count < 20 { violations.append("too few in-flight samples") }
    if distinctOrigins.count < 20 { violations.append("window did not travel along the path") }
    if samples.last?.isFlying == true { violations.append("flight did not complete within 10.2 seconds") }

    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    usage = flightEndUsage ?? usage
    let endingCPUSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    let startingCPUSeconds = Double(startingUsage.ru_utime.tv_sec) + Double(startingUsage.ru_utime.tv_usec) / 1_000_000
        + Double(startingUsage.ru_stime.tv_sec) + Double(startingUsage.ru_stime.tv_usec) / 1_000_000
    let cpuSeconds = max(0, endingCPUSeconds - startingCPUSeconds)
    let elapsed = max(0.001, flightElapsed ?? (ProcessInfo.processInfo.systemUptime - performanceStart))
    let averageCPU = cpuSeconds / elapsed * 100
    let peakRSSMiB = Double(usage.ru_maxrss) / 1_048_576
    let startingPeakRSSMiB = Double(startingUsage.ru_maxrss) / 1_048_576
    if averageCPU >= 5 { violations.append(String(format: "flight CPU %.2f%% is not below 5%%", averageCPU)) }
    if peakRSSMiB >= 100 {
        violations.append(String(
            format: "peak RSS %.2f MiB is not below 100 MiB (%.2f MiB before flight)",
            peakRSSMiB,
            startingPeakRSSMiB
        ))
    }

    if violations.isEmpty {
        print(String(
            format: "PASS: %d in-flight samples, %d distinct positions, all frames in bounds, mouse pass-through active, average CPU %.2f%%, peak RSS %.2f MiB",
            flightSamples.count,
            distinctOrigins.count,
            averageCPU,
            peakRSSMiB
        ))
        exit(0)
    }
    violations.forEach { fputs("FAIL: \($0)\n", stderr) }
    exit(1)
}

application.run()
