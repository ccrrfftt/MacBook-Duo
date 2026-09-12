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
    private(set) var displayID: CGDirectDisplayID?
    private(set) var frame = NSRect.zero
    private var stream: SCStream?
    var hasStream: Bool { stream != nil }
    private var ownApplication: SCRunningApplication?
    private var generation = 0
    private var streamStartTask: Task<Void, Error>?
    private var stoppingTask: Task<Void, Never>?
    private struct Target {
        let screen: NSScreen
        let filter: SCContentFilter
        let id: CGDirectDisplayID
        let frame: NSRect
        let scale: CGFloat
    }
    private var target: Target?
    private var standbyStream: SCStream?
    private var preparationTask: Task<Target, Error>?
    private var preparationGeneration = 0
    private let logger = Logger(subsystem: "studio.prototype.HingeGlass.Global", category: "Capture")

    /// Enumerates display/application metadata only. No stream is started and
    /// no desktop pixels are acquired until start() is called by a lid change.
    func prepare() async throws -> NSScreen {
        if let target {
            if let current = NSScreen.screens.first(where: { $0.displayID == target.id }),
               current.frame == target.frame, current.backingScaleFactor == target.scale,
               CGDisplayIsActive(target.id) != 0 {
                try prepareStandbyStream(target)
                return current
            }
            invalidatePreparation()
        }
        let token = preparationGeneration
        if preparationTask == nil { preparationTask = Task { try await loadTarget() } }
        do {
            let result = try await preparationTask!.value
            guard token == preparationGeneration, !Task.isCancelled else { throw CancellationError() }
            target = result
            try prepareStandbyStream(result)
            preparationTask = nil
            return result.screen
        } catch {
            if token == preparationGeneration { preparationTask = nil }
            throw error
        }
    }

    func invalidatePreparation() {
        preparationGeneration += 1
        preparationTask?.cancel()
        preparationTask = nil
        target = nil
        standbyStream = nil
    }

    private func prepareStandbyStream(_ target: Target) throws {
        guard standbyStream == nil else { return }
        let candidate = SCStream(filter: target.filter, configuration: configuration(screen: target.screen), delegate: self)
        try candidate.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        standbyStream = candidate // Deliberately do not call startCapture here.
    }

    private func loadTarget() async throws -> Target {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
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
            try Task.checkCancellation()
            ownApplication = allContent.applications.first(where: { $0.processID == ownPID })
        }
        guard let ownApp = ownApplication, ownApp.processID == ownPID else {
            throw Failure.cannotExcludeSelf
        }
        let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        return Target(screen: screen, filter: filter, id: display.displayID,
                      frame: screen.frame, scale: screen.backingScaleFactor)
    }

    func start() async throws -> NSScreen {
        stop()
        let token = generation
        // A rapid reversal waits for the preceding stream to fully stop.
        await stoppingTask?.value
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        stoppingTask = nil
        let screen = try await prepare()
        guard token == generation, !Task.isCancelled, let target, let stream = standbyStream else { throw CancellationError() }
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        frame = target.frame
        displayID = target.id
        standbyStream = nil
        self.stream = stream
        let request = Task { try await stream.startCapture() }
        streamStartTask = request
        do {
            try await request.value
            guard token == generation, !Task.isCancelled else {
                if self.stream === stream { stop() }
                throw CancellationError()
            }
            streamStartTask = nil
            logger.info("Capture started on demand, maximum FPS 30")
            return screen
        } catch {
            if self.stream === stream { stop() }
            throw error
        }
    }

    func stop() {
        generation += 1
        let previous = stream
        let pendingStart = streamStartTask
        streamStartTask = nil
        stream = nil
        frame = .zero
        displayID = nil
        if let previous {
            let precedingStop = stoppingTask
            stoppingTask = Task {
                await precedingStop?.value
                // If an opening movement cancelled startup, stop only after
                // that startup request resolves; never leave a late stream alive.
                _ = try? await pendingStart?.value
                do {
                    try await previous.stopCapture()
                    logger.info("Capture stopped; no desktop stream remains")
                    if let target, stream == nil { try prepareStandbyStream(target) }
                } catch {
                    logger.error("Capture stop reported: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func configuration(screen: NSScreen) -> SCStreamConfiguration {
        let result = SCStreamConfiguration()
        // Match the Metal view's backing pixels; point-sized capture visibly
        // softened text the instant an otherwise clear overlay appeared.
        result.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        result.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        result.captureResolution = .best
        result.colorSpaceName = CGColorSpace.sRGB
        result.pixelFormat = kCVPixelFormatType_32BGRA
        result.minimumFrameInterval = CMTime(value: 1, timescale: 30)
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
