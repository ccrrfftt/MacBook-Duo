import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Page {
        case setup
        case test
    }

    @Published var page: Page = .setup
    @Published var desktopImage: NSImage?
    @Published var importedFileName = ""
    @Published var useSensor = true
    @Published var simulatedAngle = LiveEffectPolicy.defaultOpenAngle
    @Published var controlsHidden = false
    @Published var showOriginal = false
    @Published var calibrationMessage = ""
    @Published var openAngle = LiveEffectPolicy.defaultOpenAngle {
        didSet { onConfigurationChange?() }
    }
    @Published var globalStatus = "效果已停止"
    @Published var globalRunning = false
    @Published var settingsVisible = true {
        didSet { onConfigurationChange?() }
    }
    @Published var showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon") {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            onDockVisibilityChange?()
            onConfigurationChange?()
        }
    }
    var startGlobal: (() -> Void)?
    var stopGlobal: (() -> Void)?
    var previewGlobal: (() -> Void)?
    var hideSettings: (() -> Void)?
    var openPermissionSettings: (() -> Void)?
    var onConfigurationChange: (() -> Void)?
    var onDockVisibilityChange: (() -> Void)?

    var currentAngle: Double { useSensor && sensor.isAvailable ? sensor.angle : simulatedAngle }

    func saveOpenAngle() {
        setOpenAngle(currentAngle)
    }

    func setOpenAngle(_ value: Double) {
        guard value.isFinite, value >= 1, value <= 180 else {
            calibrationMessage = "请先打开屏幕，再保存展开终点"
            controlsHidden = false
            return
        }
        openAngle = value
        UserDefaults.standard.set(value, forKey: "calibratedOpenAngle")
        calibrationMessage = "已保存：\(Int(value.rounded()))° 时完全清晰"
    }

    let sensor = LidAngleSensor()

    init() {
        openAngle = LiveEffectPolicy.openAngle(
            saved: UserDefaults.standard.object(forKey: "calibratedOpenAngle") as? Double,
            legacy: UserDefaults(suiteName: "studio.prototype.HingeGlass")?.object(forKey: "calibratedOpenAngle") as? Double
        )
    }

    func importScreenshot() {
        let panel = NSOpenPanel()
        panel.title = "选择桌面截图"
        panel.message = "请选择一张完整的桌面截图，用作玻璃层下方的内容。"
        panel.prompt = "导入截图"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }

        desktopImage = image
        importedFileName = url.lastPathComponent
    }

    func startTest() {
        guard desktopImage != nil else { return }
        controlsHidden = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            page = .test
        }
    }

    func returnToSetup() {
        controlsHidden = false
        withAnimation(.easeInOut(duration: 0.3)) {
            page = .setup
        }
    }

}
