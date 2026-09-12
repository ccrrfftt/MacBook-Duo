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
        precondition(E.captureFPS(remaining: 0, velocity: 0) == 1)
        precondition(E.captureFPS(remaining: 0.5, velocity: 0) == 30)
        precondition(E.captureFPS(remaining: 0, velocity: -20) == 30)
        precondition(E.captureFPS(remaining: 0.0001, velocity: 0) == 30)
        precondition(E.retryDelay(failures: 100) == 30)
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: 0.9))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: .infinity))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: -.infinity))
        precondition(!DesktopTransitionPolicy.canBegin(frameAge: .nan))
        precondition(DesktopTransitionPolicy.canBegin(frameAge: 0.02))
        precondition(DesktopTransitionPolicy.captureFPS(remaining: 0, velocity: 0, presenting: true) == 30)
        precondition(DesktopTransitionPolicy.captureFPS(remaining: 0, velocity: 0, presenting: false) == 1)

        var rate = CaptureRateState()
        rate.desired = 1
        precondition(rate.begin() == 1)
        precondition(rate.begin() == nil)
        rate.finish(succeeded: false)
        precondition(rate.applied == 30)
        precondition(rate.begin() == 1)
        rate.desired = 30
        rate.finish(succeeded: true)
        precondition(rate.applied == 1)
        precondition(rate.begin() == 30)
        rate.finish(succeeded: true)
        precondition(rate.applied == 30 && rate.begin() == nil)

        precondition(SensorPollingPolicy.interval(now: 1, lastMovement: 0) == 0.1)
        precondition(SensorPollingPolicy.interval(now: 0.1, lastMovement: 0) == 1.0 / 30)
        precondition(!BackgroundPolicy.shouldMonitor(settingsVisible: false, effectEnabled: false, suspended: false))
        precondition(BackgroundPolicy.shouldMonitor(settingsVisible: false, effectEnabled: true, suspended: false))
        precondition(BackgroundPolicy.shouldMonitor(settingsVisible: true, effectEnabled: false, suspended: false))
        precondition(!BackgroundPolicy.shouldMonitor(settingsVisible: true, effectEnabled: true, suspended: true))
        print("PASS: calibration, continuous endpoint transitions, fresh entry frames, live capture during return, serial capture-rate updates, failure retry, adaptive polling, background/sleep policy")
    }
}
