import AppKit
import CoreVideo

/// WindowServer/Metal integration check; uses only a generated checkerboard.
/// Run locally with script/test_render_transitions.sh, not in headless CI.
@MainActor
final class RenderTransitionCheck {
    private let renderer = GlassMetalView()
    private var window: NSPanel!
    private var stage = 0
    private var firstFrames = 0
    private var deadline: Timer?

    func start() {
        precondition(renderer.pipelineAvailable)
        window = NSPanel(contentRect: NSRect(x: 80, y: 80, width: 480, height: 320),
                         styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "MacBook Duo · Render check"
        window.animationBehavior = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = renderer
        window.alphaValue = 0
        renderer.onFirstFrameReady = { [weak self] in
            guard let self else { return }
            precondition(self.window.alphaValue == 0)
            self.firstFrames += 1
            self.window.alphaValue = 1
            self.renderer.setLiveAngle(20)
        }
        renderer.onSettled = { [weak self] in self?.settled() }
        renderer.beginLivePresentation()
        renderer.receive(Self.checkerboard())
        window.orderFrontRegardless()
        deadline = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            print("FAIL: GPU transition callback timed out")
            exit(1)
        }
    }

    private func settled() {
        switch stage {
        case 0:
            // Reverse a return before it reaches clear. The obsolete return
            // must not deliver a settled callback for the new target.
            stage = 1
            renderer.setLiveAngle(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in
                precondition(stage == 1)
                stage = 2
                renderer.setLiveAngle(15)
            }
        case 1:
            preconditionFailure("A reversing animation settled prematurely")
        case 2:
            stage = 3
            renderer.setLiveAngle(0)
        case 3:
            stage = 4
            renderer.endLivePresentation()
            window.orderOut(nil)
            let draws = renderer.drawCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                precondition(renderer.drawCount == draws, "Hidden renderer kept drawing")
                window.alphaValue = 0
                renderer.beginLivePresentation()
                renderer.receive(Self.checkerboard())
                window.orderFrontRegardless()
            }
        case 4:
            stage = 5
            renderer.setLiveAngle(0)
        case 5:
            precondition(firstFrames == 2)
            deadline?.invalidate()
            renderer.endLivePresentation()
            window.orderOut(nil)
            print("PASS: two prepared first frames, interrupted return, presented zero endpoints, re-entry, hidden renderer paused; draws=\(renderer.drawCount)")
            NSApp.terminate(nil)
        default: preconditionFailure("Unexpected render callback")
        }
    }

    private static func checkerboard() -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey: true,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        precondition(CVPixelBufferCreate(nil, 960, 640, kCVPixelFormatType_32BGRA, attributes, &result) == kCVReturnSuccess)
        let buffer = result!
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<640 {
            for x in 0..<960 {
                let offset = y * stride + x * 4
                let color: UInt8 = (x / 32 + y / 32).isMultiple(of: 2) ? 220 : 55
                bytes[offset] = color
                bytes[offset + 1] = color
                bytes[offset + 2] = color
                bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

@main struct RenderTransitionTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let check = RenderTransitionCheck()
        check.start()
        withExtendedLifetime(check) { app.run() }
    }
}
