@preconcurrency import AppKit
@preconcurrency import ServiceManagement
import Darwin
import FlyingSnowfluffCore
import QuartzCore

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // PetController already constrains authored flight paths and snaps a
    // user-dragged pet back into the selected screen on mouse-up. Avoid asking
    // AppKit to recompute notch/Space constraints on every 60 Hz flight frame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class FlyingSnowfluffAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var eventServer: PetEventServer?
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let atlasURLs = [
            Bundle.main.url(forResource: "spritesheet@2x", withExtension: "png"),
            Bundle.main.url(forResource: "spritesheet", withExtension: "png")
        ].compactMap { $0 }
        guard let atlas = try? SpriteAtlas.loadBest(candidates: atlasURLs) else {
            NSAlert(error: StartupError.missingSpritesheet).runModal()
            NSApp.terminate(nil)
            return
        }

        let controller = PetController(atlas: atlas)
        self.controller = controller
        statusMenu = StatusMenuController(controller: controller)

        let server = PetEventServer { [weak controller] event in
            controller?.receive(event)
        }
        do {
            try server.start()
        } catch {
            NSLog("FlyingSnowfluff event bridge failed to start: \(error)")
        }
        eventServer = server
        controller.start()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        controller?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventServer?.stop()
        controller?.stop()
    }

    private enum StartupError: LocalizedError {
        case missingSpritesheet
        var errorDescription: String? { "FlyingSnowfluff.app 缺少有效的高清或兼容图集。" }
    }
}

final class PetController: NSObject {
    private let window: PetPanel
    private let windowRoot: NSView
    private let contentView: PetContentView
    private var settings: PetSettings
    private var coordinator = PetStateCoordinator()
    private var scheduler = ActionScheduler()
    private var planner = FlightPlanner()
    private var activeScreen: NSScreen?
    private var currentActivity: PetActivity = .ambient
    private var frameTimer: Timer?
    private var stateTimer: Timer?
    private var displayLink: CADisplayLink?
    private var flightRun: FlightRun?
    private var gesturePicker = GesturePicker()
    private var dialoguePicker = DialoguePicker()
    private var ambientBubbleCooldown = BubbleCooldown()
    private var toolBubbleCooldown = BubbleCooldown(interval: 60)
    private var gestureEndWork: DispatchWorkItem?
    private var gestureGeneration = 0
    private var gestureActive = false
    private var gestureAutomatic = false
    private let defaults: UserDefaults
    private var motionObserver: NSObjectProtocol?
    #if FLYING_SNOWFLUFF_QA
    private var qaSystemReduceMotion: Bool?
    #endif
    private var systemReduceMotion: Bool {
        #if FLYING_SNOWFLUFF_QA
        if let qaSystemReduceMotion { return qaSystemReduceMotion }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private var effectiveReduceMotion: Bool { settings.reduceMotion || systemReduceMotion }

    private struct FlightRun {
        let path: CubicBezierPath
        let centerInWindow: NSPoint
        let restingWindowSize: NSSize
        let flightWindowFrame: NSRect
        let started: Double
        let duration: Double
        let right: Bool
        var currentPoint: Point2D
    }
    private var nextFlightWork: DispatchWorkItem?
    private var nextAmbientWork: DispatchWorkItem?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localLinkTestWorkItem: DispatchWorkItem?
    private var lastHookEventAt: Date?
    private(set) var isFlying = false
    private(set) var isHidden = false

    private static let contextMenuHintKey = "contextMenuHintShown.v1"

    private let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6]

    init(atlas: SpriteAtlas, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = PetSettingsStore.load(from: defaults)
        contentView = PetContentView(atlas: atlas, petHeight: settings.height)
        windowRoot = NSView(frame: contentView.frame)
        window = PetPanel(
            contentRect: windowRoot.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        windowRoot.wantsLayer = true
        windowRoot.layer?.backgroundColor = NSColor.clear.cgColor
        windowRoot.addSubview(contentView)
        contentView.layer?.actions = ["transform": NSNull()]
        window.contentView = windowRoot
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false

        contentView.spriteView.reduceMotion = effectiveReduceMotion
        contentView.spriteView.quietCompanionship = settings.quietCompanionship
        contentView.spriteView.onSingleClick = { [weak self] in self?.performPlayfulAction() }
        contentView.spriteView.onDoubleClick = { [weak self] in self?.startFlight(userInitiated: true) }
        contentView.spriteView.onMovedByDrag = { [weak self] in self?.didFinishDrag() }
        contentView.spriteView.onDragBegan = { [weak self] in self?.cancelGesture() }
        activeScreen = NSScreen.main
        positionInitially()
    }

    func start() {
        window.orderFrontRegardless()
        if motionObserver == nil {
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.motionPreferencesChanged() }
        }
        startFrameTimer()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshActivity()
        }
        installMouseMonitors()
        scheduleNextFlight()
        scheduleNextAmbientAction()
        if settings.launchAtLogin { setLaunchAtLogin(true) }
        showContextMenuHintIfNeeded()
    }

    func stop() {
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        motionObserver = nil
        frameTimer?.invalidate()
        stateTimer?.invalidate()
        stopFlight()
        nextFlightWork?.cancel()
        nextAmbientWork?.cancel()
        localLinkTestWorkItem?.cancel()
        cancelGesture()
        contentView.spriteView.animationsEnabled = false
        contentView.spriteView.updateMotion(at: CACurrentMediaTime())
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    func receive(_ envelope: HookEnvelope) {
        let hadGesture = gestureActive
        cancelGesture()
        localLinkTestWorkItem?.cancel()
        localLinkTestWorkItem = nil
        lastHookEventAt = Date(timeIntervalSince1970: envelope.timestamp)
        coordinator.receive(envelope.event, at: Date(timeIntervalSince1970: envelope.timestamp))
        refreshActivity()
        if hadGesture { setAnimationRow(row(for: currentActivity)) }
    }

    func installContextMenu(_ menu: NSMenu, willOpen: @escaping () -> Void = {}) {
        contentView.installContextMenu(menu, willOpen: willOpen)
    }

    func runLocalLinkTest() {
        localLinkTestWorkItem?.cancel()
        let lastRealEventAtStart = lastHookEventAt
        coordinator.receive(.toolRunning, at: Date())
        refreshActivity(presentDialogue: false)
        contentView.showBubble("本地测试：正在工作……", duration: 2)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lastHookEventAt == lastRealEventAtStart else { return }
            self.coordinator.receive(.ready, at: Date())
            self.refreshActivity(presentDialogue: false)
            self.contentView.showBubble("本地测试：完成！", duration: 3)
            self.localLinkTestWorkItem = nil
        }
        localLinkTestWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func statusMenuPresentation(at date: Date = Date()) -> StatusMenuPresentation {
        StatusMenuPresentation.make(
            settings: settings,
            isHidden: isHidden,
            loginItemEnabled: loginItemEnabled,
            activity: currentActivity,
            lastHookEventAt: lastHookEventAt,
            now: date
        )
    }

    private func refreshActivity(presentDialogue: Bool = true) {
        let activity = coordinator.current()
        guard activity != currentActivity else { return }
        currentActivity = activity
        if activity != .ambient && activity != .idle && isFlying { finishFlight() }
        guard !gestureActive else { return }
        switch activity {
        case .needsInput:
            setAnimationRow(6)
            if presentDialogue { showDialogue(.needsInput) }
        case .failed:
            setAnimationRow(5)
            if presentDialogue { showDialogue(.failed) }
        case .ready:
            setAnimationRow(8)
            if presentDialogue { showDialogue(.ready) }
        case .working, .toolRunning:
            setAnimationRow(7)
            // One shared cooldown avoids chattering on alternating pre/post-tool hooks.
            if presentDialogue && !isHidden && toolBubbleCooldown.allow(now: CACurrentMediaTime()) {
                showDialogue(activity == .toolRunning ? .toolRunning : .working)
            }
        case .ambient, .idle:
            if !isFlying { setAnimationRow(0) }
        }
    }

    private func startFrameTimer() {
        frameTimer?.invalidate()
        guard !settings.isPaused, !isHidden, !effectiveReduceMotion else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/8.0, repeats: true) { [weak self] _ in
            guard let self, !self.isHidden, !self.settings.isPaused else { return }
            self.contentView.spriteView.reduceMotion = self.effectiveReduceMotion
            if self.contentView.spriteView.hasLivelyArtwork {
                if !self.isFlying { self.contentView.spriteView.updateMotion(at: CACurrentMediaTime()) }
            } else {
                let row = self.contentView.spriteView.row
                let next = self.effectiveReduceMotion ? 0 : (self.contentView.spriteView.column + 1) % self.frameCounts[row]
                self.contentView.spriteView.setFrame(row: row, column: next)
            }
        }
        frameTimer?.tolerance = 0.03
    }

    private func showDialogue(_ scene: DialogueScene) {
        guard !isHidden else { return }
        let line = dialoguePicker.next(for: scene)
        contentView.showBubble(line.text, duration: line.duration)
    }

    private func setAnimationRow(_ row: Int) {
        contentView.spriteView.setFrame(row: row, column: 0)
        let motions = ["idle", "flyRight", "flyLeft", "wave", "sway", "failed", "waiting", "working", "celebrate"]
        contentView.spriteView.playMotion(motions[min(8,max(0,row))])
        updateMousePassThrough()
    }

    private func performPlayfulAction(automatic: Bool = false, selected: PetGesture? = nil) {
        guard !settings.isPaused, !isHidden, !isFlying, !contentView.spriteView.isDragging else { return }
        guard let gesture = selected ?? gesturePicker.next(from: automatic ? PetGesture.allCases : [.wave,.shy,.tilt]) else { return }
        cancelGesture(); gestureActive = true; gestureAutomatic = automatic
        let generation = gestureGeneration
        contentView.spriteView.setFrame(row: gesture == .sway ? 4 : 3, column: 0)
        contentView.spriteView.playMotion(gesture.rawValue)
        if !automatic || ambientBubbleCooldown.allow(now: CACurrentMediaTime()) {
            showDialogue(.interaction)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.gestureGeneration == generation else { return }
            self.gestureActive = false
            self.setAnimationRow(self.row(for: self.currentActivity))
        }
        gestureEndWork = work
        let duration = contentView.spriteView.motionDuration(gesture.rawValue) ?? (gesture == .nap ? 3.6 : 1.85)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelGesture() {
        gestureEndWork?.cancel(); gestureEndWork = nil
        gestureGeneration += 1; gestureActive = false; gestureAutomatic = false
    }

    private var allowsAutomaticAction: Bool {
        MotionPolicy.allowsAutomaticFlight(activity: currentActivity, paused: settings.isPaused,
            hidden: isHidden, hovering: contentView.spriteView.isHovering || contentView.spriteView.isDragging,
            quiet: settings.quietCompanionship, reduceMotion: effectiveReduceMotion)
    }

    func startFlight(userInitiated: Bool = false) {
        guard !settings.isPaused, !isHidden, !isFlying, !contentView.spriteView.isDragging else { return }
        if !userInitiated && !allowsAutomaticAction { scheduleNextFlight(); return }
        guard !effectiveReduceMotion else { return }
        cancelGesture()
        nextFlightWork?.cancel()
        nextAmbientWork?.cancel()
        isFlying = true
        window.ignoresMouseEvents = true
        contentView.spriteView.isHovering = false

        let selectedFrame = flightFrame()
        let petSize = contentView.spriteView.frame.size
        let rect = Rect2D(
            x: selectedFrame.minX,
            y: selectedFrame.minY,
            width: selectedFrame.width,
            height: selectedFrame.height
        )
        var generated = planner.makePath(
            in: rect,
            marginX: petSize.width / 2 + 8,
            marginY: petSize.height / 2 + 8
        )
        let safe = rect.insetBy(dx: petSize.width / 2 + 8, dy: petSize.height / 2 + 8)
        let petCenterInWindow = contentView.spriteView.convert(
            NSPoint(x: contentView.spriteView.bounds.midX, y: contentView.spriteView.bounds.midY),
            to: nil
        )
        let center = window.convertPoint(toScreen: petCenterInWindow)
        generated.start = Point2D(
            x: min(safe.maxX, max(safe.minX, center.x)),
            y: min(safe.maxY, max(safe.minY, center.y))
        )
        let path = generated
        setAnimationRow(path.end.x >= path.start.x ? 1 : 2)
        if userInitiated { showDialogue(.flight) }

        let restingWindowSize = window.frame.size
        window.setFrame(selectedFrame, display: false)
        moveFlyingContent(
            to: path.start,
            centerInWindow: petCenterInWindow,
            flightWindowFrame: selectedFrame
        )
        flightRun = FlightRun(
            path: path,
            centerInWindow: petCenterInWindow,
            restingWindowSize: restingWindowSize,
            flightWindowFrame: selectedFrame,
            started: CACurrentMediaTime(),
            duration: scheduler.nextFlightDuration(reduceMotion: false),
            right: path.end.x >= path.start.x,
            currentPoint: path.start
        )
        let link = contentView.displayLink(target: self, selector: #selector(advanceFlight(_:)))
        let fps = Float(FlightMotion.preferredFramesPerSecond(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        displayLink = link
        link.add(to: .main, forMode: .common)
        contentView.spriteView.setFlightPose(progress: 0, right: path.end.x >= path.start.x)
    }

    @objc private func advanceFlight(_ link: CADisplayLink) {
        guard var flight = flightRun, !settings.isPaused, !isHidden, !effectiveReduceMotion else { finishFlight(); return }
        let raw = min(1, (CACurrentMediaTime()-flight.started)/flight.duration)
        let eased = raw*raw*(3-2*raw)
        let point = flight.path.point(at:eased)
        moveFlyingContent(
            to: point,
            centerInWindow: flight.centerInWindow,
            flightWindowFrame: flight.flightWindowFrame
        )
        flight.currentPoint = point
        flightRun = flight
        let next = flight.path.point(at:min(1,eased+0.002))
        let previous = flight.path.point(at:max(0,eased-0.002))
        let dx = next.x-previous.x, dy = next.y-previous.y
        let right = abs(dx) > 0.01 ? dx >= 0 : flight.right
        let bank = atan2(dy,abs(dx)+0.001) * 0.08 * (right ? -1.0 : 1.0)
        contentView.spriteView.setFlightPose(progress:raw,right:right,bank:bank)
        if raw >= 1 { finishFlight() }
    }

    private func stopFlight() {
        displayLink?.invalidate(); displayLink = nil
        if let flight = flightRun {
            let scale = window.backingScaleFactor
            let origin = NSPoint(
                x: ((flight.currentPoint.x - flight.centerInWindow.x) * scale).rounded() / scale,
                y: ((flight.currentPoint.y - flight.centerInWindow.y) * scale).rounded() / scale
            )
            window.setFrame(NSRect(origin: origin, size: flight.restingWindowSize), display: false)
            contentView.layer?.transform = CATransform3DIdentity
        }
        flightRun = nil; isFlying = false
    }

    private func moveFlyingContent(
        to point: Point2D,
        centerInWindow: NSPoint,
        flightWindowFrame: NSRect
    ) {
        let scale = window.backingScaleFactor
        let x = ((point.x - flightWindowFrame.minX - centerInWindow.x) * scale).rounded() / scale
        let y = ((point.y - flightWindowFrame.minY - centerInWindow.y) * scale).rounded() / scale
        contentView.layer?.transform = CATransform3DMakeTranslation(
            x,
            y,
            0
        )
    }

    private func finishFlight() {
        stopFlight()
        activeScreen = screenContainingPetCenter() ?? activeScreen
        setAnimationRow(currentActivity == .ambient ? 0 : row(for: currentActivity))
        updateMousePassThrough()
        scheduleNextFlight()
        scheduleNextAmbientAction()
        contentView.spriteView.settleAfterDrag()
    }

    private func row(for activity: PetActivity) -> Int {
        switch activity {
        case .needsInput: return 6
        case .failed: return 5
        case .ready: return 8
        case .working, .toolRunning: return 7
        case .ambient, .idle: return 0
        }
    }

    private func flightFrame() -> NSRect {
        guard settings.crossDisplays, NSScreen.screens.count > 1 else {
            return (activeScreen ?? screenContainingPetCenter() ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let current = activeScreen ?? screenContainingPetCenter() ?? NSScreen.main
        let target = NSScreen.screens.filter { $0 != current }.randomElement() ?? current
        guard let current, let target else { return NSScreen.screens[0].visibleFrame }
        let currentRect = Rect2D(
            x: current.visibleFrame.minX,
            y: current.visibleFrame.minY,
            width: current.visibleFrame.width,
            height: current.visibleFrame.height
        )
        let targetRect = Rect2D(
            x: target.visibleFrame.minX,
            y: target.visibleFrame.minY,
            width: target.visibleFrame.width,
            height: target.visibleFrame.height
        )
        guard currentRect.formsSolidBoundingUnion(with: targetRect) else {
            return current.visibleFrame
        }
        return current.visibleFrame.union(target.visibleFrame)
    }

    private func scheduleNextFlight() {
        nextFlightWork?.cancel()
        guard !settings.isPaused, !isHidden, !settings.quietCompanionship, !effectiveReduceMotion else { return }
        let delay = scheduler.nextFlightDelay(reduceMotion: settings.reduceMotion)
        let work = DispatchWorkItem { [weak self] in self?.startFlight() }
        nextFlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleNextAmbientAction() {
        nextAmbientWork?.cancel()
        guard !settings.isPaused, !isHidden, !settings.quietCompanionship, !effectiveReduceMotion else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.allowsAutomaticAction && !self.isFlying { self.performPlayfulAction(automatic: true) }
            self.scheduleNextAmbientAction()
        }
        nextAmbientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scheduler.nextAmbientDelay(), execute: work)
    }

    private func installMouseMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateMousePassThrough()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateMousePassThrough()
        }
        updateMousePassThrough()
    }

    private func updateMousePassThrough() {
        guard !isFlying else {
            window.ignoresMouseEvents = true
            contentView.spriteView.clearGaze()
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let opaque = contentView.spriteView.containsOpaquePixel(screenPoint: mouseLocation)
        window.ignoresMouseEvents = !opaque
        contentView.spriteView.isHovering = opaque
        if opaque && gestureActive && gestureAutomatic {
            cancelGesture()
            setAnimationRow(row(for: currentActivity))
        }
        if opaque {
            contentView.spriteView.look(at: mouseLocation)
        } else {
            contentView.spriteView.clearGaze()
        }
    }

    private func positionInitially() {
        let frame = (activeScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrameOrigin(NSPoint(
            x: frame.maxX - window.frame.width - 36,
            y: frame.minY + 48
        ))
    }

    private func showContextMenuHintIfNeeded() {
        guard !defaults.bool(forKey: Self.contextMenuHintKey) else { return }
        defaults.set(true, forKey: Self.contextMenuHintKey)
        contentView.showBubble("右键点我可以打开设置哦～", duration: 5)
    }

    private func didFinishDrag() {
        activeScreen = screenContainingPetCenter() ?? activeScreen
        clampToVisibleScreen()
        setAnimationRow(row(for: currentActivity))
        contentView.spriteView.settleAfterDrag()
        updateMousePassThrough()
    }

    private func screenContainingPetCenter() -> NSScreen? {
        let center = petCenterInScreenCoordinates()
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func petCenterInScreenCoordinates() -> NSPoint {
        let centerInWindow = contentView.spriteView.convert(
            NSPoint(x: contentView.spriteView.bounds.midX, y: contentView.spriteView.bounds.midY),
            to: nil
        )
        return window.convertPoint(toScreen: centerInWindow)
    }

    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        persistSettings()
        if paused {
            stopFlight(); cancelGesture(); frameTimer?.invalidate()
            nextFlightWork?.cancel()
            nextAmbientWork?.cancel()
            setAnimationRow(0)
        } else {
            startFrameTimer()
            setAnimationRow(row(for: currentActivity))
            scheduleNextFlight()
            scheduleNextAmbientAction()
        }
        contentView.spriteView.animationsEnabled = !paused && !isHidden
        contentView.spriteView.updateMotion(at: CACurrentMediaTime())
        updateMousePassThrough()
    }

    func show() {
        let wasHidden = isHidden
        isHidden = false
        window.orderFrontRegardless()
        contentView.spriteView.animationsEnabled = !settings.isPaused
        if wasHidden { startFrameTimer(); scheduleNextFlight(); scheduleNextAmbientAction() }
        guard wasHidden else { return }
        showDialogue(.reappear)
        #if FLYING_SNOWFLUFF_QA
        qaShowTransitionCount += 1
        #endif
    }

    func toggleHidden() {
        if isHidden {
            show()
        } else {
            isHidden = true
            stopFlight(); cancelGesture(); frameTimer?.invalidate()
            nextFlightWork?.cancel(); nextAmbientWork?.cancel()
            setAnimationRow(row(for: currentActivity))
            contentView.spriteView.animationsEnabled = false
            contentView.spriteView.updateMotion(at: CACurrentMediaTime())
            window.orderOut(nil)
        }
    }

    func setHeight(_ height: Double) {
        let oldCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        settings.height = height
        contentView.updatePetHeight(settings.height)
        window.setContentSize(contentView.frame.size)
        window.setFrameOrigin(NSPoint(
            x: oldCenter.x - window.frame.width / 2,
            y: oldCenter.y - window.frame.height / 2
        ))
        persistSettings()
        clampToVisibleScreen()
    }

    func setCrossDisplays(_ enabled: Bool) {
        settings.crossDisplays = enabled
        persistSettings()
    }

    func setReduceMotion(_ enabled: Bool) {
        settings.reduceMotion = enabled
        persistSettings()
        motionPreferencesChanged()
    }

    private func motionPreferencesChanged() {
        contentView.spriteView.reduceMotion = effectiveReduceMotion
        if effectiveReduceMotion { stopFlight(); cancelGesture(); setAnimationRow(row(for: currentActivity)) }
        contentView.spriteView.updateMotion(at: CACurrentMediaTime())
        startFrameTimer()
        scheduleNextFlight()
        scheduleNextAmbientAction()
    }

    func setQuietCompanionship(_ enabled: Bool) {
        settings.quietCompanionship = enabled
        contentView.spriteView.quietCompanionship = enabled
        if enabled { stopFlight(); cancelGesture(); setAnimationRow(row(for: currentActivity)) }
        persistSettings(); scheduleNextFlight(); scheduleNextAmbientAction()
    }

    func previewGesture(_ gesture: PetGesture) { performPlayfulAction(selected: gesture) }

    private func clampToVisibleScreen() {
        guard let screen = activeScreen ?? NSScreen.main else { return }
        let pet = contentView.spriteView.convert(contentView.spriteView.bounds, to: nil)
        let center = window.convertPoint(toScreen: NSPoint(x: pet.midX, y: pet.midY))
        let safe = screen.visibleFrame.insetBy(dx: pet.width/2+8, dy: pet.height/2+8)
        let target = NSPoint(x: min(safe.maxX,max(safe.minX,center.x)), y: min(safe.maxY,max(safe.minY,center.y)))
        window.setFrameOrigin(NSPoint(x: window.frame.minX+target.x-center.x, y: window.frame.minY+target.y-center.y))
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        if enabled {
            if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        persistSettings()
    }

    var currentSettings: PetSettings { settings }
    var loginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    #if FLYING_SNOWFLUFF_QA
    private(set) var qaShowTransitionCount = 0

    struct QASnapshot {
        let frame: NSRect
        let petFrame: NSRect
        let visibleFrame: NSRect
        let isFlying: Bool
        let isWindowVisible: Bool
        let ignoresMouseEvents: Bool
        let animationRow: Int
    }

    func qaSnapshot() -> QASnapshot {
        let petRectInWindow = contentView.spriteView.convert(contentView.spriteView.bounds, to: nil)
        let petFrame: NSRect
        if let flight = flightRun {
            petFrame = NSRect(
                x: flight.currentPoint.x - petRectInWindow.width / 2,
                y: flight.currentPoint.y - petRectInWindow.height / 2,
                width: petRectInWindow.width,
                height: petRectInWindow.height
            )
        } else {
            petFrame = window.convertToScreen(petRectInWindow)
        }
        return QASnapshot(
            frame: window.frame,
            petFrame: petFrame,
            visibleFrame: (activeScreen ?? NSScreen.main)?.visibleFrame ?? .zero,
            isFlying: isFlying,
            isWindowVisible: window.isVisible,
            ignoresMouseEvents: window.ignoresMouseEvents,
            animationRow: contentView.spriteView.row
        )
    }

    var qaContextMenu: NSMenu? { contentView.spriteView.menu }
    var qaLastHookEventAt: Date? { lastHookEventAt }
    var qaCurrentActivity: PetActivity { currentActivity }
    var qaMotionFrame: String? { contentView.spriteView.qaMotionFrame }
    var qaFrameTimerActive: Bool { frameTimer?.isValid == true }
    var qaAutomaticActionsScheduled: Bool { nextFlightWork?.isCancelled == false && nextAmbientWork?.isCancelled == false }
    func qaSetSystemReduceMotion(_ value: Bool) { qaSystemReduceMotion = value; motionPreferencesChanged() }
    #endif

    private func persistSettings() {
        PetSettingsStore.save(settings, to: defaults)
    }
}

final class StatusMenuController: NSObject, NSMenuDelegate {
    static let codexLinkHelpText = "在终端运行 codex，输入 /hooks，逐项核对并信任页面实际列出、且只调用 flyingsnowfluffctl 的本地处理器。配置共 6 条（包含 SessionEnd），当前客户端页面可能只列 5 项；不要因为页面未列 SessionEnd 而删除配置。完成当前任务后重启 Codex Desktop，再新建任务即可看到工作、工具、等待输入、失败和完成动画。"

    private weak var controller: PetController?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let pauseItem = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "")
    private let hideItem = NSMenuItem(title: "隐藏", action: #selector(toggleHidden), keyEquivalent: "")
    private let crossItem = NSMenuItem(title: "跨屏巡游", action: #selector(toggleCrossDisplays), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let reduceMotionItem = NSMenuItem(title: "减少动态效果", action: #selector(toggleReduceMotion), keyEquivalent: "")
    private let quietItem = NSMenuItem(title: "安静陪伴", action: #selector(toggleQuiet), keyEquivalent: "")
    private let linkStatusItem = NSMenuItem(title: "Codex 联动：尚未收到事件", action: nil, keyEquivalent: "")
    private let lastEventItem = NSMenuItem(title: "最近事件：无", action: nil, keyEquivalent: "")

    init(controller: PetController) {
        self.controller = controller
        super.init()
        statusItem.autosaveName = "local.flyingsnowfluff.aemeath.status-item"
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "飞行雪绒")
        statusItem.button?.toolTip = "飞行雪绒·爱弥斯"
        menu.delegate = self
        linkStatusItem.isEnabled = false
        lastEventItem.isEnabled = false
        menu.addItem(linkStatusItem)
        menu.addItem(lastEventItem)
        let testLink = NSMenuItem(title: "测试联动显示（本地）", action: #selector(testCodexLink), keyEquivalent: "")
        testLink.target = self
        menu.addItem(testLink)
        let linkHelp = NSMenuItem(title: "Codex 联动说明…", action: #selector(showCodexLinkHelp), keyEquivalent: "")
        linkHelp.target = self
        menu.addItem(linkHelp)
        menu.addItem(.separator())
        for item in [pauseItem, hideItem] { item.target = self; menu.addItem(item) }
        let fly = NSMenuItem(title: "立即飞行", action: #selector(flyNow), keyEquivalent: "")
        fly.target = self
        menu.addItem(fly)
        let previews = NSMenuItem(title: "动作预览", action: nil, keyEquivalent: "")
        let previewMenu = NSMenu()
        for (index,title) in ["挥手", "害羞", "歪头", "整理目镜", "抱翼打盹", "跟着节拍", "探头回望"].enumerated() {
            let item = NSMenuItem(title:title,action:#selector(previewAction(_:)),keyEquivalent:"")
            item.tag=index;item.target=self;previewMenu.addItem(item)
        }
        previews.submenu=previewMenu;menu.addItem(previews)
        menu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (title, value) in [("小巧", 176), ("均衡（默认）", 208), ("大", 256), ("特大", 320)] {
            let item = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        for item in [quietItem, crossItem, loginItem, reduceMotionItem] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出飞行雪绒", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        controller.installContextMenu(menu) { [weak self] in
            self?.refreshPresentation()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPresentation()
    }

    private func refreshPresentation() {
        guard let controller else { return }
        let presentation = controller.statusMenuPresentation()
        linkStatusItem.title = presentation.linkStatusTitle
        lastEventItem.title = presentation.lastEventTitle
        pauseItem.title = presentation.pauseTitle
        hideItem.title = presentation.hideTitle
        crossItem.state = presentation.crossDisplays ? .on : .off
        loginItem.state = presentation.loginItemEnabled ? .on : .off
        reduceMotionItem.state = presentation.reduceMotion ? .on : .off
        quietItem.state = controller.currentSettings.quietCompanionship ? .on : .off
    }

    @objc private func togglePause() {
        guard let controller else { return }
        controller.setPaused(!controller.currentSettings.isPaused)
    }

    @objc private func toggleHidden() { controller?.toggleHidden() }
    @objc private func flyNow() { controller?.startFlight(userInitiated: true) }
    @objc private func testCodexLink() { controller?.runLocalLinkTest() }
    @objc private func toggleQuiet() {
        guard let controller else { return }
        controller.setQuietCompanionship(!controller.currentSettings.quietCompanionship)
    }
    @objc private func previewAction(_ sender: NSMenuItem) {
        guard PetGesture.allCases.indices.contains(sender.tag) else { return }
        controller?.previewGesture(PetGesture.allCases[sender.tag])
    }

    @objc private func showCodexLinkHelp() {
        let alert = NSAlert()
        alert.messageText = "Codex 联动"
        alert.informativeText = Self.codexLinkHelpText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func setSize(_ sender: NSMenuItem) { controller?.setHeight(Double(sender.tag)) }

    @objc private func toggleCrossDisplays() {
        guard let controller else { return }
        controller.setCrossDisplays(!controller.currentSettings.crossDisplays)
    }

    @objc private func toggleLaunchAtLogin() {
        guard let controller else { return }
        controller.setLaunchAtLogin(!controller.loginItemEnabled)
    }

    @objc private func toggleReduceMotion() {
        guard let controller else { return }
        controller.setReduceMotion(!controller.currentSettings.reduceMotion)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    #if FLYING_SNOWFLUFF_QA
    var qaMenu: NSMenu { menu }
    var qaLinkStatusTitle: String { linkStatusItem.title }
    var qaLastEventTitle: String { lastEventItem.title }
    var qaPauseTitle: String { pauseItem.title }
    var qaHideTitle: String { hideItem.title }
    #endif
}
