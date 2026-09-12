import AppKit

/// Notifications wake the controller; no recovery timer runs while locked/asleep.
@MainActor
final class DesktopLifecycle {
    var onSuspend: ((String) -> Void)?
    var onResume: ((String) -> Void)?
    var onDisplayChange: (() -> Void)?
    var onSpaceChange: (() -> Void)?
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.onSuspend?("lock") }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.onResume?("lock") }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "system"),
                               (NSWorkspace.screensDidSleepNotification, "display"),
                               (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observe(workspace, name) { [weak self] in self?.onSuspend?(reason) }
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "system"),
                               (NSWorkspace.screensDidWakeNotification, "display"),
                               (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observe(workspace, name) { [weak self] in self?.onResume?(reason) }
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.onSpaceChange?() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.onDisplayChange?() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observations.append((center, token))
    }

    func shutdown() {
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
    }
}
