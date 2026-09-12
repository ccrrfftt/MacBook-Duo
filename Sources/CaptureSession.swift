import AppKit
import ScreenCaptureKit
import CoreMedia
import OSLog

@MainActor
final class CaptureSession: NSObject, @preconcurrency SCStreamOutput, SCStreamDelegate {
    enum Failure: LocalizedError {
        case permission, noInternalDisplay, cannotExcludeSelf, noGPU
        var errorDescription: String? {
            switch self {
            case .permission: return "屏幕录制权限尚未生效。请打开权限设置，允许后退出并重新打开本应用。"
            case .noInternalDisplay: return "未找到可用的 MacBook 内建屏幕。"
            case .cannotExcludeSelf: return "暂时无法排除本应用窗口，已停止捕获以避免画面重复。"
            case .noGPU: return "Metal 渲染不可用。"
            }
        }
    }
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onFailure: ((Error) -> Void)?
    private var screen: NSScreen?
    private(set) var displayID: CGDirectDisplayID?
    private(set) var frame = NSRect.zero
    private var stream: SCStream?
    private var ownApplication: SCRunningApplication?
    private var generation = 0
    private var rate = CaptureRateState()
    private var rateTask: Task<Void, Never>?
    private var retryTimer: Timer?
    private var rateFailures = 0
    private let logger = Logger(subsystem: "studio.prototype.HingeGlass.Global", category: "Capture")

    func start(fps: Int32, allowPermissionPrompt: Bool) async throws -> NSScreen {
        stop()
        let token = generation
        guard CGPreflightScreenCaptureAccess() ||
                (allowPermissionPrompt && CGRequestScreenCaptureAccess()) else { throw Failure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
              let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else {
            throw Failure.noInternalDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let application = content.applications.first(where: { $0.processID == ownPID }) {
            ownApplication = application
        }
        if ownApplication == nil {
            // A first start from the menu bar may have no visible setup window.
            let allContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            ownApplication = allContent.applications.first(where: { $0.processID == ownPID })
        }
        guard let ownApp = ownApplication, ownApp.processID == ownPID else {
            throw Failure.cannotExcludeSelf
        }
        self.screen = screen
        frame = screen.frame
        displayID = display.displayID
        rate = CaptureRateState(initial: fps)
        let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration(fps: fps, screen: screen), delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        do {
            try await stream.startCapture()
            guard token == generation, !Task.isCancelled else {
                try? await stream.stopCapture()
                throw CancellationError()
            }
            logger.info("Capture started, maximum FPS \(fps)")
            return screen
        } catch {
            if self.stream === stream { stop() }
            throw error
        }
    }

    func stop() {
        generation += 1
        rateTask?.cancel()
        rateTask = nil
        retryTimer?.invalidate()
        retryTimer = nil
        rateFailures = 0
        let previous = stream
        stream = nil
        screen = nil
        frame = .zero
        displayID = nil
        if let previous { Task { try? await previous.stopCapture() } }
    }

    func setRate(_ fps: Int32) {
        rate.desired = fps
        updateRate()
    }

    private func updateRate() {
        guard rateTask == nil, retryTimer == nil, let stream, let screen,
              let fps = rate.begin() else { return }
        let token = generation
        rateTask = Task { @MainActor in
            do {
                try await stream.updateConfiguration(configuration(fps: fps, screen: screen))
                guard token == generation else { return }
                rate.finish(succeeded: true)
                rateFailures = 0
                rateTask = nil
                updateRate() // Apply a newer request that arrived while awaiting.
            } catch {
                guard token == generation else { return }
                rate.finish(succeeded: false) // Never mark a failed rate as applied.
                rateTask = nil
                rateFailures += 1
                logger.error("Capture rate update failed: \(error.localizedDescription, privacy: .public)")
                let timer = Timer(timeInterval: LiveEffectPolicy.retryDelay(failures: rateFailures), repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.retryTimer = nil
                        self?.updateRate()
                    }
                }
                timer.tolerance = 0.2
                retryTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func configuration(fps: Int32, screen: NSScreen) -> SCStreamConfiguration {
        let result = SCStreamConfiguration()
        // Match the Metal view's backing pixels; point-sized capture visibly
        // softened text the instant an otherwise clear overlay appeared.
        result.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        result.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        result.captureResolution = .best
        result.colorSpaceName = CGColorSpace.sRGB
        result.pixelFormat = kCVPixelFormatType_32BGRA
        result.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        result.queueDepth = 3
        result.showsCursor = false
        result.capturesAudio = false
        return result
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard self.stream === stream, type == .screen, buffer.isValid,
              let info = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        onFrame?(pixels)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            stop()
            onFailure?(error)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
