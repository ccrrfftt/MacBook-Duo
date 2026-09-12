import AppKit
import CoreVideo

private final class DesktopGlassPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class DesktopOverlay {
    private let panel: NSPanel
    private let renderer = GlassMetalView()
    private var preparing = false
    private var requestedAngle = 0.0
    var isPresenting: Bool { panel.isVisible }
    var isVisible: Bool { panel.isVisible && !preparing }
    var uploadCount: Int { renderer.uploadCount }
    var drawCount: Int { renderer.drawCount }
    var onSettled: (() -> Void)? {
        get { renderer.onSettled }
        set { renderer.onSettled = newValue }
    }

    init(screen: NSScreen) throws {
        guard renderer.device != nil, renderer.pipelineAvailable else { throw CaptureSession.Failure.noGPU }
        panel = DesktopGlassPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false, screen: screen)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.animationBehavior = .none
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = renderer
        renderer.onFirstFrameReady = { [weak self] in
            guard let self, self.preparing, self.panel.isVisible else { return }
            self.preparing = false
            // The zero-angle frame has finished on the GPU before the panel is
            // revealed. AppKit must not crossfade the window over the desktop.
            self.panel.alphaValue = 1
            self.renderer.setLiveAngle(self.requestedAngle)
        }
    }

    func present(buffer: CVPixelBuffer?, angle: Double) {
        requestedAngle = angle
        if !panel.isVisible {
            guard angle > 0, let buffer else { return }
            preparing = true
            panel.alphaValue = 0
            renderer.beginLivePresentation()
            renderer.receive(buffer)
            panel.orderFrontRegardless()
            return
        }
        if preparing && angle == 0 { hide(); return }
        if let buffer { renderer.receive(buffer) }
        if !preparing { renderer.setLiveAngle(angle) }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
        preparing = false
        requestedAngle = 0
        renderer.endLivePresentation()
    }
}
