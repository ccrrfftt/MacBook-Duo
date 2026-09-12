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
        remaining > 0.008 || abs(velocity) > 2 ? 30 : 2
    }
    static func retryDelay(failures: Int) -> TimeInterval {
        min(30, Double(max(1, failures)) * 2)
    }
}
