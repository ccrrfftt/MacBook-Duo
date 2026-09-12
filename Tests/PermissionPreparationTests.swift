import Foundation
@main struct PolicyTests {
    static func main() async {
        typealias P = ScreenCapturePermissionPreparation
        precondition(!P.shouldReset(userConfirmed: false, actualBundleID: P.bundleID))
        precondition(!P.shouldReset(userConfirmed: true, actualBundleID: "another.app"))
        precondition(!P.shouldReset(userConfirmed: true, actualBundleID: nil))
        precondition(P.shouldReset(userConfirmed: true, actualBundleID: P.bundleID))
        let result = await P.prepare()
        precondition(result == nil)
        typealias E = LiveEffectPolicy
        // A fresh install, missing legacy key, or invalid preference uses 100°.
        precondition(E.openAngle(saved: nil, legacy: nil) == 100)
        precondition(E.openAngle(saved: nil, legacy: 0) == 100)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, 181] {
            precondition(E.openAngle(saved: invalid, legacy: nil) == 100)
        }
        // Preserve explicit calibration, including migration from the old app.
        precondition(E.openAngle(saved: 95, legacy: 120) == 95)
        precondition(E.openAngle(saved: 120, legacy: nil) == 120)
        precondition(E.openAngle(saved: nil, legacy: 90) == 90)
        precondition(E.openAngle(saved: .nan, legacy: 95) == 95)
        // Opening is gradual below 100° and clear at/above it in either direction.
        let at90 = E.remaining(angle: 90, velocity: 0, endpoint: 100, preview: false)
        let at95 = E.remaining(angle: 95, velocity: 0, endpoint: 100, preview: false)
        precondition(at90 > at95 && at95 > 0)
        precondition(abs(at90 - 0.1) < 0.000001)
        for angle in [100.0, 105, 120, 180] {
            for velocity in [-100.0, 0, 100] {
                precondition(E.remaining(angle: angle, velocity: velocity, endpoint: 100, preview: false) == 0)
            }
        }
        precondition(E.remaining(angle: 0, velocity: 0, endpoint: 97, preview: false) == 1)
        precondition(E.remaining(angle: 97, velocity: 0, endpoint: 97, preview: false) == 0)
        precondition(E.remaining(angle: 120, velocity: 0, endpoint: 97, preview: false) == 0)
        precondition(E.remaining(angle: .nan, velocity: 0, endpoint: 97, preview: false) == 0)
        precondition(E.remaining(angle: 20, velocity: 0, endpoint: 0, preview: false) == 0)
        precondition(E.remaining(angle: 120, velocity: 0, endpoint: 97, preview: true) == 0.35)
        precondition(E.remaining(angle: 90, velocity: -100, endpoint: 97, preview: false) > E.remaining(angle: 90, velocity: 0, endpoint: 97, preview: false))
        precondition(E.captureFPS(remaining: 0, velocity: 0) == 2)
        precondition(E.captureFPS(remaining: 0.5, velocity: 0) == 30)
        precondition(E.captureFPS(remaining: 0, velocity: -20) == 30)
        precondition(E.retryDelay(failures: 100) == 30)
        print("PASS: 100-degree default, saved calibration, clear endpoint, permission safety, prediction, capture budget, retry backoff")
    }
}
