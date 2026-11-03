import Foundation
import WatchConnectivity
import WatchKit

/// Talks to the iPhone: starts the test with your starting heart rate,
/// streams live heart rate, and sends Record HR presses.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    enum Phase { case idle, reading, running, finished }

    @Published var phase: Phase = .idle
    @Published var phoneReady = false
    @Published var maxHR = 0
    @Published var stopHR = 0
    @Published var stageLabel = "Get ready"
    @Published var lastRecorded = ""
    @Published var vo2: Double?
    @Published var stoppedAtThreshold = false
    @Published var message: String?

    let workout = WorkoutManager()
    private var lastSent = Date.distantPast

    override init() {
        super.init()
        workout.onHeartRate = { [weak self] bpm in self?.heartRate(bpm) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Asks the iPhone for the latest age settings.
    func refresh(then next: (() -> Void)? = nil) {
        send(["type": "config"], reply: { [weak self] r in
            self?.applyContext(r)
            next?()
        }, failed: { next?() })
    }

    func startTest() {
        message = nil
        refresh { [weak self] in
            guard let self else { return }
            guard self.phoneReady else {
                self.message = WCSession.default.isReachable
                    ? "Enter your age in the iPhone app first."
                    : "Can't reach your iPhone. Open Fitness Test on it and try again."
                return
            }
            self.beginReading()
        }
    }

    private func beginReading() {
        phase = .reading
        Task {
            await workout.requestAuthorization()
            do {
                try await workout.start()
            } catch {
                phase = .idle
                message = "Couldn't read your heart rate."
            }
        }
    }

    func recordHR() {
        let hr = Int(workout.heartRate.rounded())
        guard hr > 0 else { lastRecorded = "No heart rate yet"; return }
        send(["type": "record", "hr": hr], reply: { [weak self] r in
            self?.lastRecorded = r["message"] as? String ?? "Recorded \(hr)"
            WKInterfaceDevice.current().play(.success)
        }, failed: { [weak self] in
            self?.lastRecorded = "iPhone not reachable"
            WKInterfaceDevice.current().play(.failure)
        })
    }

    func stopTest() {
        send(["type": "stop"], reply: nil, failed: { [weak self] in
            guard let self else { return }
            self.phase = .idle
            Task { await self.workout.end(save: false) }
        })
    }

    func done() {
        phase = .idle
        vo2 = nil
        lastRecorded = ""
    }

    private func heartRate(_ bpm: Double) {
        let hr = Int(bpm.rounded())
        switch phase {
        case .reading:
            // First reading is the starting heart rate, and it begins the test.
            phase = .running
            stageLabel = "Get ready"
            lastRecorded = "Starting HR: \(hr) bpm"
            vo2 = nil
            send(["type": "start", "hr": hr], reply: { [weak self] r in
                guard let self, (r["ok"] as? Bool) == false else { return }
                self.cancel(r["message"] as? String ?? "The iPhone couldn't start the test.")
            }, failed: { [weak self] in
                self?.cancel("Open Fitness Test on your iPhone and try again.")
            })
        case .running:
            if Date().timeIntervalSince(lastSent) >= 1 {
                lastSent = Date()
                send(["type": "hr", "hr": hr], reply: nil, failed: nil)
            }
        default:
            break
        }
    }

    private func cancel(_ text: String) {
        message = text
        phase = .idle
        WKInterfaceDevice.current().play(.failure)
        Task { await workout.end(save: false) }
    }

    private func send(_ msg: [String: Any], reply: (([String: Any]) -> Void)?, failed: (() -> Void)?) {
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { failed?(); return }
        s.sendMessage(msg, replyHandler: { r in
            Task { @MainActor in reply?(r) }
        }, errorHandler: { _ in
            Task { @MainActor in failed?() }
        })
    }

    fileprivate func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "state":
            if let label = m["label"] as? String, label != stageLabel {
                stageLabel = label
                if label.hasPrefix("Stage") { WKInterfaceDevice.current().play(.directionUp) }
            }
        case "config":
            applyContext(m)
        case "prompt":
            WKInterfaceDevice.current().play(.notification)
        case "result":
            guard phase == .running else { return }
            vo2 = m["vo2"] as? Double
            stoppedAtThreshold = (m["reason"] as? String) == "threshold"
            phase = .finished
            WKInterfaceDevice.current().play(.stop)
            Task { await workout.end(save: true) }
        default:
            break
        }
    }

    fileprivate func applyContext(_ c: [String: Any]) {
        phoneReady = c["ready"] as? Bool ?? false
        maxHR = c["maxHR"] as? Int ?? 0
        stopHR = c["stopHR"] as? Int ?? 0
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.applyContext(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.applyContext(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}
