import AppKit

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "studio.prototype.HingeGlass.Global")
for app in apps {
    let policy: String
    switch app.activationPolicy {
    case .regular: policy = "regular (Dock)"
    case .accessory: policy = "accessory (menu bar, no Dock)"
    case .prohibited: policy = "prohibited"
    @unknown default: policy = "unknown"
    }
    print("pid=\(app.processIdentifier) activation=\(policy)")
}
if apps.isEmpty { print("MacBook Duo is not running"); exit(1) }
