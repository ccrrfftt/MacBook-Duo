import AppKit
import CoreVideo

private final class DesktopGlassPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class DesktopOverlay {
    private let panel: NSPanel
    private let renderer = GlassMetalView()
    var isVisible: Bool { panel.isVisible }
    var settled: Bool { renderer.settled }
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
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = renderer
    }

    func present(buffer: CVPixelBuffer?, angle: Double) {
        if let buffer { renderer.receive(buffer) }
        renderer.setLiveAngle(angle)
        if renderer.readyForDisplay && !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
        renderer.isPaused = true
    }
}
