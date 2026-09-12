import SwiftUI
import AppKit

@main
struct HingeGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { appDelegate.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var model: AppModel?
    private var controller: GlobalDesktopController?
    private var keyMonitor: Any?
    private var hideObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        window.minSize = NSSize(width: 980, height: 660)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: RootView(model: model).preferredColorScheme(.dark))
        window.center()
        self.window = window
        model.hideSettings = { [weak self] in self?.hideSettings() }
        model.onDockVisibilityChange = { [weak self] in self?.applyDockVisibility() }
        let controller = GlobalDesktopController(model: model)
        self.controller = controller
        controller.onShowSettings = { [weak self] in self?.showSettings() }
        controller.onHideSettings = { [weak self] in self?.hideSettings() }
        applyDockVisibility()
        showSettings()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, let model = self.model, model.page == .test else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "h": if !event.isARepeat { model.controlsHidden.toggle() }; return nil
                case "k": if !event.isARepeat { model.saveOpenAngle() }; return nil
                case "b": if !event.isARepeat { model.showOriginal.toggle() }; return nil
                default: break
                }
            }
            if event.keyCode == 53 { model.controlsHidden = false; return nil }
            return event
        }
        hideObserver = NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification,
                                                              object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.settingsVisible = false }
        }
    }

    private func applyDockVisibility() {
        guard let model else { return }
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
    }

    func showSettings() {
        model?.returnToSetup()
        model?.settingsVisible = true
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideSettings() {
        window?.orderOut(nil)
        model?.settingsVisible = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideSettings()
        return false // Reuse the settings window; closing it never stops the engine.
    }

    func windowDidMiniaturize(_ notification: Notification) { model?.settingsVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model?.settingsVisible = true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "打开设置", action: #selector(openFromDock), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func openFromDock() { showSettings() }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let hideObserver { NotificationCenter.default.removeObserver(hideObserver) }
    }
}
