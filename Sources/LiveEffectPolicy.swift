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

    static let previewTilt = 28.0

    static func remaining(angle: Double, velocity: Double, endpoint: Double, preview: Bool) -> Double {
        if preview { return 0.35 }
        guard angle.isFinite, velocity.isFinite, endpoint.isFinite, endpoint > 0 else { return 0 }
        // The saved endpoint always means clear, even during a closing movement.
        guard angle < endpoint else { return 0 }
        // Fade prediction out at the clear endpoint; a hard cutoff used to add
        // up to four degrees of effect as soon as the lid crossed the boundary.
        let distance = min(1, max(0, (endpoint - angle) / 8))
        let prediction = max(-4, min(0, velocity * 0.04)) * distance * distance * (3 - 2 * distance)
        return min(1, max(0, 1 - max(0, angle + prediction) / endpoint))
    }
    static func visualTilt(angle: Double, endpoint: Double, strength: Double = 1, velocity: Double = 0) -> Double {
        guard strength.isFinite, strength > 0 else { return 0 }
        let amount = remaining(angle: angle, velocity: velocity, endpoint: endpoint, preview: false)
        // Preserve the upstream visual response and screenshot strength curve.
        return 80 * (1 - pow(1 - amount, 1 / strength))
    }
    static func retryDelay(failures: Int) -> TimeInterval {
        min(30, Double(max(1, failures)) * 2)
    }
}

/// A hidden overlay may only start from a recent frame. Animation back to clear
/// keeps its stream until the zero-angle frame has actually been presented.
enum DesktopTransitionPolicy {
    static func canBegin(frameAge: TimeInterval) -> Bool {
        frameAge.isFinite && frameAge >= 0 && frameAge <= 1.0 / 15
    }
    static func needsCapture(tilt: Double, presenting: Bool, settingsVisible: Bool) -> Bool {
        !settingsVisible && (tilt > 0 || presenting)
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
