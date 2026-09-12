import Foundation

@main struct RuntimePolicyTests {
    static func main() {
        typealias E = LiveEffectPolicy
        precondition(E.openAngle(saved: nil, legacy: nil) == 100)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, 181] {
            precondition(E.openAngle(saved: invalid, legacy: nil) == 100)
        }
        precondition(E.openAngle(saved: 95, legacy: 120) == 95)
        precondition(E.openAngle(saved: 90, legacy: nil) == 90)
        precondition(E.openAngle(saved: .nan, legacy: 95) == 95)
        for endpoint in [90.0, 95, 100, 120] {
            precondition(E.remaining(angle: 0, velocity: 0, endpoint: endpoint, preview: false) == 1)
            for velocity in [-100.0, 0, 100] {
                precondition(E.remaining(angle: endpoint, velocity: velocity, endpoint: endpoint, preview: false) == 0)
                precondition(E.remaining(angle: 180, velocity: velocity, endpoint: endpoint, preview: false) == 0)
                // Crossing the clear endpoint must not suddenly introduce the
                // old four-degree velocity prediction, in either direction.
                let justBelow = E.remaining(angle: endpoint - 0.0001, velocity: velocity, endpoint: endpoint, preview: false)
                precondition(justBelow > 0 && justBelow < 0.00001)
            }
            var previous = 0.0
            for step in 1...1_000 {
                let angle = endpoint - Double(step) / 100
                let amount = E.remaining(angle: angle, velocity: -100, endpoint: endpoint, preview: false)
                precondition(amount >= previous && amount - previous < 0.001)
                previous = amount
            }
        }
        precondition(E.remaining(angle: .nan, velocity: 0, endpoint: 100, preview: false) == 0)
        precondition(E.remaining(angle: 20, velocity: 0, endpoint: 0, preview: false) == 0)
        precondition(E.remaining(angle: 100, velocity: 0, endpoint: 100, preview: true) == 0.35)
        precondition(E.retryDelay(failures: 100) == 30)
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: 0.9))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: .infinity))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: -.infinity))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: .nan))
        precondition(DesktopTransitionPolicy.canBegin(frameAge: 0.02))
        precondition(DesktopTransitionPolicy.needsCapture(tilt: 0, presenting: true, settingsVisible: false))
        precondition(!DesktopTransitionPolicy.needsCapture(tilt: 0, presenting: false, settingsVisible: false))
        precondition(DesktopTransitionPolicy.needsCapture(tilt: 0.001, presenting: false, settingsVisible: false))
        precondition(!DesktopTransitionPolicy.needsCapture(tilt: 20, presenting: true, settingsVisible: true))
        for endpoint in [90.0, 100, 120] {
            precondition(E.visualTilt(angle: endpoint, endpoint: endpoint) == 0)
            precondition(E.visualTilt(angle: 0, endpoint: endpoint) == 80)
            precondition(E.visualTilt(angle: endpoint / 2, endpoint: endpoint) == 40)
            for strength in [0.5, 1, 2] {
                for fraction in [0.1, 0.25, 0.75, 0.9] {
                    let upstream = 80 * (1 - pow(fraction, 1 / strength))
                    let actual = E.visualTilt(angle: endpoint * fraction, endpoint: endpoint, strength: strength)
                    precondition(abs(actual - upstream) < 1e-9)
                }
            }
        }
        precondition(E.visualTilt(angle: 80, endpoint: 100, strength: .nan) == 0)
        precondition(!DesktopTransitionPolicy.needsCapture(tilt: E.visualTilt(angle: 95, endpoint: 90), presenting: false, settingsVisible: false))
        precondition(DesktopTransitionPolicy.needsCapture(tilt: E.visualTilt(angle: 95, endpoint: 100), presenting: false, settingsVisible: false))

        precondition(SensorPollingPolicy.interval(now: 1, lastMovement: 0) == 0.1)
        precondition(SensorPollingPolicy.interval(now: 0.1, lastMovement: 0) == 1.0 / 30)
        precondition(!BackgroundPolicy.shouldMonitor(settingsVisible: false, effectEnabled: false, suspended: false))
        precondition(BackgroundPolicy.shouldMonitor(settingsVisible: false, effectEnabled: true, suspended: false))
        precondition(BackgroundPolicy.shouldMonitor(settingsVisible: true, effectEnabled: false, suspended: false))
        precondition(!BackgroundPolicy.shouldMonitor(settingsVisible: true, effectEnabled: true, suspended: true))
        print("PASS: original visual curve, adjustable clarity endpoints, continuous boundaries, fresh frames, on-demand capture, retry, polling, background/sleep policy")
    }
}
