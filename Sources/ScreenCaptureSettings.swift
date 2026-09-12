import AppKit

/// Only opens Apple's settings. Permission records are never reset by the app.
enum ScreenCaptureSettings {
    @MainActor static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
