import AppKit
import CoreVideo
import OSLog
import QuartzCore

/// Coordinates state transitions. Frames and sensor changes drive visual work.
@MainActor
final class GlobalDesktopController {
    private enum Phase { case stopped, starting, running, suspended }
    private let model: AppModel
    private let controls = DesktopControls()
    private let capture = CaptureSession()
    private let lifecycle = DesktopLifecycle()
    private var overlay: DesktopOverlay?
    private var phase = Phase.stopped
    private var sleepReasons = Set<String>()
    private var startTask: Task<Void, Never>?
    private var healthTimer: Timer?
    private var retryTimer: Timer?
    private var failures = 0
    private var latestFrame: CVPixelBuffer?
    private var latestFrameAt = -Double.infinity
    private var frameSequence = 0
    private var uploadedSequence = -1
    private var startedAt = Date()
    private var previewUntil = Date.distantPast
    private var previewRequested = false
    private var didShutdown = false
    private var diagnosticTicks = 0
    private let diagnostics = CommandLine.arguments.contains("--diagnostics")
    private let logger = Logger(subsystem: "studio.prototype.HingeGlass.Global", category: "Lifecycle")
    var onShowSettings: (() -> Void)?
    var onHideSettings: (() -> Void)?
    private var enabled: Bool { phase != .stopped }

    init(model: AppModel) {
        self.model = model
        controls.onAction = { [weak self] in self?.handle($0) }
        model.startGlobal = { [weak self] in self?.start() }
        model.stopGlobal = { [weak self] in self?.stop() }
        model.previewGlobal = { [weak self] in self?.preview() }
        model.openPermissionSettings = { ScreenCaptureSettings.openSettings() }
        model.onConfigurationChange = { [weak self] in
            self?.updateMonitoring()
            self?.updateEffect()
            self?.refreshMenu()
        }
        model.sensor.onChange = { [weak self] in self?.updateEffect(); self?.refreshMenu() }
        capture.onFrame = { [weak self] buffer in
            guard let self, self.sleepReasons.isEmpty else { return }
            self.latestFrame = buffer // Retain one CPU-side frame while the overlay is hidden.
            self.latestFrameAt = CACurrentMediaTime()
            self.frameSequence += 1
            self.updateEffect()
        }
        capture.onFailure = { [weak self] in self?.captureFailed($0) }
        lifecycle.onSuspend = { [weak self] reason in
            guard let self else { return }
            self.sleepReasons.insert(reason)
            if self.enabled { self.suspend(message: "屏幕已休眠或锁定，唤醒后自动恢复") }
            self.updateMonitoring()
        }
        lifecycle.onResume = { [weak self] reason in
            guard let self else { return }
            self.sleepReasons.remove(reason)
            self.updateMonitoring()
            if self.enabled, self.sleepReasons.isEmpty { self.start(automatically: true) }
        }
        lifecycle.onDisplayChange = { [weak self] in self?.displayChanged() }
        lifecycle.onSpaceChange = { [weak self] in self?.overlay?.hide(); self?.updateEffect() }
        updateMonitoring()
        refreshMenu()
    }

    private func handle(_ action: DesktopControls.Action) {
        switch action {
        case .toggle: enabled ? stop() : start()
        case .preview: preview()
        case .calibrate:
            if model.sensor.isAvailable { model.setOpenAngle(model.sensor.angle) }
        case .settings: onShowSettings?()
        case .stopAndShow: stop(); onShowSettings?()
        case .permissions: ScreenCaptureSettings.openSettings()
        case .dock: model.showDockIcon.toggle()
        case .quit: shutdown(); NSApp.terminate(nil)
        }
    }

    func start(automatically: Bool = false) {
        guard phase != .starting, phase != .running else { return }
        guard controls.emergencyShortcutAvailable else {
            setStatus("紧急停止快捷键不可用，未启动效果。请退出其他 MacBook Duo 副本。")
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        phase = .starting
        model.globalRunning = true
        guard sleepReasons.isEmpty else { suspend(message: "等待屏幕唤醒后恢复"); return }
        updateMonitoring()
        guard model.sensor.isAvailable,
              Date().timeIntervalSince(model.sensor.lastSuccessfulUpdate) < 2 else {
            if automatically { suspend(message: "等待铰链传感器恢复"); scheduleRetry() }
            else { stop(message: "铰链传感器不可用，可使用截图预览。") }
            return
        }
        if !automatically { failures = 0 }
        setStatus("正在启动实时效果…")
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fps = LiveEffectPolicy.captureFPS(remaining: remaining, velocity: model.sensor.velocity)
                let screen = try await capture.start(fps: fps, allowPermissionPrompt: !automatically)
                guard !Task.isCancelled, phase == .starting else { return }
                overlay = try DesktopOverlay(screen: screen)
                overlay?.onSettled = { [weak self] in
                    guard let self, self.remaining == 0 else { return }
                    if self.diagnostics { self.logger.info("Transition: clear frame presented; hiding overlay") }
                    self.overlay?.hide()
                    self.updateEffect()
                    self.refreshMenu()
                }
                phase = .running
                startedAt = Date()
                if previewRequested {
                    previewUntil = Date().addingTimeInterval(8)
                    previewRequested = false
                }
                startTask = nil
                startHealthTimer()
                if !automatically { onHideSettings?() }
                updateEffect()
                setStatus("效果已启用，关闭设置窗口后继续在菜单栏运行")
                logger.info("Effect started")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                startTask = nil
                if automatically { captureFailed(error) }
                else { stop(message: error.localizedDescription); onShowSettings?() }
            }
        }
    }

    func stop(message: String = "效果已停止，应用仍在菜单栏运行") {
        phase = .stopped
        model.globalRunning = false
        releaseCapture()
        previewUntil = .distantPast
        previewRequested = false
        failures = 0
        updateMonitoring()
        setStatus(message)
    }

    private func releaseCapture() {
        startTask?.cancel()
        startTask = nil
        healthTimer?.invalidate()
        healthTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        overlay?.hide()
        overlay = nil
        latestFrame = nil
        latestFrameAt = -Double.infinity
        uploadedSequence = -1
        capture.stop()
    }

    private func suspend(message: String) {
        guard enabled else { return }
        phase = .suspended
        releaseCapture()
        updateMonitoring()
        setStatus(message)
    }

    private func captureFailed(_ error: Error) {
        guard enabled else { return }
        if !CGPreflightScreenCaptureAccess() {
            stop(message: CaptureSession.Failure.permission.localizedDescription)
            return // A revoked permission never starts automatic prompting/retry loops.
        }
        failures += 1
        suspend(message: "捕获暂时中断，将自动重试：\(error.localizedDescription)")
        scheduleRetry()
        logger.error("Capture interrupted: \(error.localizedDescription, privacy: .public)")
    }

    private func scheduleRetry() {
        guard enabled, sleepReasons.isEmpty, retryTimer == nil else { return }
        let timer = Timer(timeInterval: LiveEffectPolicy.retryDelay(failures: failures), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTimer = nil
                self?.start(automatically: true)
            }
        }
        timer.tolerance = 0.2
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func preview() {
        if phase == .running {
            previewUntil = Date().addingTimeInterval(8)
            onHideSettings?()
            updateEffect()
        } else {
            previewRequested = true
            start()
        }
    }

    private var remaining: Double {
        LiveEffectPolicy.remaining(angle: model.sensor.angle, velocity: model.sensor.velocity,
                                   endpoint: model.openAngle, preview: Date() < previewUntil)
    }

    private func updateEffect() {
        guard phase == .running, sleepReasons.isEmpty, let overlay else { return }
        guard !model.settingsVisible else {
            overlay.hide()
            capture.setRate(1)
            return
        }
        let amount = remaining
        capture.setRate(DesktopTransitionPolicy.captureFPS(remaining: amount,
                        velocity: model.sensor.velocity, presenting: overlay.isPresenting))
        guard amount > 0 || overlay.isPresenting else { return }
        // Wait for capture to catch up after the idle rate changes. Never expose
        // the cached one-FPS frame (or a retained old tilt) on entry.
        if !overlay.isPresenting {
            guard DesktopTransitionPolicy.canBegin(frameAge: CACurrentMediaTime() - latestFrameAt) else { return }
            if diagnostics { logger.info("Transition: preparing fresh frame, age=\(CACurrentMediaTime() - self.latestFrameAt)") }
        }
        let needsUpload = !overlay.isPresenting || uploadedSequence != frameSequence
        overlay.present(buffer: needsUpload ? latestFrame : nil, angle: amount * 80)
        if needsUpload && latestFrame != nil { uploadedSequence = frameSequence }
    }

    private func updateMonitoring() {
        if BackgroundPolicy.shouldMonitor(settingsVisible: model.settingsVisible, effectEnabled: enabled,
                                          suspended: !sleepReasons.isEmpty) {
            model.sensor.start()
        } else { model.sensor.stop() }
    }

    private func startHealthTimer() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        timer.tolerance = 0.2
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkHealth() {
        guard phase == .running else { return }
        if Date().timeIntervalSince(model.sensor.lastSuccessfulUpdate) > 2 ||
            (latestFrame == nil && Date().timeIntervalSince(startedAt) > 8) {
            failures += 1
            suspend(message: "等待传感器或首帧恢复")
            scheduleRetry()
            return
        }
        displayChanged()
        updateEffect() // Low-frequency health and preview-expiry check, no forced render.
        refreshMenu()
        if diagnostics {
            diagnosticTicks += 1
            if diagnosticTicks % 5 == 0 {
                logger.info("Performance: frames=\(self.frameSequence) uploads=\(self.overlay?.uploadCount ?? 0) draws=\(self.overlay?.drawCount ?? 0) visible=\(self.overlay?.isVisible ?? false)")
            }
        }
    }

    private func displayChanged() {
        guard phase == .running, let id = capture.displayID else { return }
        let screen = NSScreen.screens.first(where: { $0.displayID == id })
        guard screen == nil || screen?.frame != capture.frame || CGDisplayIsActive(id) == 0 else { return }
        suspend(message: "显示器配置变化，正在恢复")
        scheduleRetry()
    }

    private func setStatus(_ message: String) {
        if model.globalStatus != message { model.globalStatus = message }
        refreshMenu()
    }

    private func refreshMenu() {
        let text = phase == .running
            ? "\(overlay?.isVisible == true ? "效果显示中" : "后台运行") · \(Int(model.sensor.angle.rounded()))° / 终点 \(Int(model.openAngle.rounded()))°"
            : model.globalStatus
        controls.update(status: text, enabled: enabled, showDock: model.showDockIcon)
    }

    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        stop()
        model.sensor.stop()
        controls.shutdown()
        lifecycle.shutdown()
    }
}
