import Foundation

/// Pure behavior shared by the controller and hardware-independent tests.
enum LiveEffectPolicy {
    static let defaultOpenAngle = 100.0

    static func openAngle(saved: Double?, legacy: Double?) -> Double {
        for candidate in [saved, legacy] {
            if let angle = candidate, angle.isFinite, (1...180).contains(angle) {
                return angle
            }
        }
        return defaultOpenAngle
    }

    static func remaining(angle: Double, velocity: Double, endpoint: Double, preview: Bool) -> Double {
        if preview { return 0.35 }
        guard angle.isFinite, velocity.isFinite, endpoint.isFinite, endpoint > 0 else { return 0 }
        // The saved endpoint always means clear, even during a closing movement.
        guard angle < endpoint else { return 0 }
        let prediction = max(-4, min(0, velocity * 0.04))
        return min(1, max(0, 1 - max(0, angle + prediction) / endpoint))
    }
    static func captureFPS(remaining: Double, velocity: Double) -> Int32 {
        remaining > 0.008 || abs(velocity) > 2 ? 30 : 1
    }
    static func retryDelay(failures: Int) -> TimeInterval {
        min(30, Double(max(1, failures)) * 2)
    }
}

/// Only a successful configuration update advances the applied capture rate.
struct CaptureRateState {
    var desired: Int32
    private(set) var applied: Int32
    private var pending: Int32?
    init(initial: Int32 = 30) { desired = initial; applied = initial }
    mutating func begin() -> Int32? {
        guard pending == nil, desired != applied else { return nil }
        pending = desired
        return pending
    }
    mutating func finish(succeeded: Bool) {
        if succeeded, let pending { applied = pending }
        pending = nil
    }
}

enum SensorPollingPolicy {
    static func interval(now: TimeInterval, lastMovement: TimeInterval) -> TimeInterval {
        now - lastMovement < 0.6 ? 1.0 / 30 : 0.1
    }
}

enum BackgroundPolicy {
    static func shouldMonitor(settingsVisible: Bool, effectEnabled: Bool, suspended: Bool) -> Bool {
        !suspended && (settingsVisible || effectEnabled)
    }
}
