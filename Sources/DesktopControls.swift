import AppKit
import Carbon

/// Owns menu-bar UI and Carbon registrations; it does not own capture state.
@MainActor
final class DesktopControls: NSObject {
    enum Action { case toggle, preview, calibrate, settings, stopAndShow, permissions, dock, quit }
    var onAction: ((Action) -> Void)?
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let status = NSMenuItem(title: "效果已停止", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "开启效果", action: nil, keyEquivalent: "")
    private let dockItem = NSMenuItem(title: "在 Dock 中显示", action: nil, keyEquivalent: "")
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var emergencyShortcutAvailable = false

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "MacBook Duo")
        item.button?.setAccessibilityLabel("MacBook Duo")
        let menu = NSMenu()
        menu.addItem(status)
        menu.addItem(.separator())
        toggleItem.action = #selector(toggle)
        toggleItem.target = self
        menu.addItem(toggleItem)
        for (title, action) in [
            ("测试效果（8 秒）", #selector(preview)),
            ("保存当前屏幕角度", #selector(calibrate)),
            ("打开设置…", #selector(settings)),
            ("停止效果并打开设置  ⌘⇧Esc", #selector(stopAndShow)),
            ("屏幕录制权限设置…", #selector(permissions))
        ] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        dockItem.action = #selector(dock)
        dockItem.target = self
        menu.addItem(dockItem)
        let quit = NSMenuItem(title: "退出 MacBook Duo", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        registerHotKeys()
    }

    func update(status text: String, enabled: Bool, showDock: Bool) {
        if status.title != text { status.title = text; item.button?.toolTip = text }
        let title = enabled ? "停止效果  ⌘⇧G" : "开启效果  ⌘⇧G"
        if toggleItem.title != title { toggleItem.title = title }
        dockItem.state = showDock ? .on : .off
    }

    func shutdown() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func toggle() { onAction?(.toggle) }
    @objc private func preview() { onAction?(.preview) }
    @objc private func calibrate() { onAction?(.calibrate) }
    @objc private func settings() { onAction?(.settings) }
    @objc private func stopAndShow() { onAction?(.stopAndShow) }
    @objc private func permissions() { onAction?(.permissions) }
    @objc private func dock() { onAction?(.dock) }
    @objc private func quit() { onAction?(.quit) }

    private func registerHotKeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let controls = Unmanaged<DesktopControls>.fromOpaque(pointer).takeUnretainedValue()
            switch id.id {
            case 1: controls.onAction?(.stopAndShow)
            case 2: controls.onAction?(.toggle)
            case 3: controls.onAction?(.calibrate)
            default: return OSStatus(eventNotHandledErr)
            }
            return noErr
        }, 1, &event, pointer, &handler)
        guard result == noErr else { return }
        for (id, key) in [(UInt32(1), UInt32(kVK_Escape)), (2, UInt32(kVK_ANSI_G)), (3, UInt32(kVK_ANSI_K))] {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(key, UInt32(cmdKey | shiftKey),
                                   EventHotKeyID(signature: 0x48474C53, id: id),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                hotKeys.append(ref)
                if id == 1 { emergencyShortcutAvailable = true }
            } else if id == 1 { break }
        }
    }
}
