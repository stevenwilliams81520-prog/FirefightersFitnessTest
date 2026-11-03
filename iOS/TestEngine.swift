import Foundation
import AVFoundation
import UIKit
import WatchConnectivity

/// Runs the Chester Step Test on the iPhone: metronome, voice prompts,
/// stage timing, heart rate readings from the watch, and the VO₂max estimate.
@MainActor
final class TestEngine: NSObject, ObservableObject {
    enum Phase { case setup, running, finished }
    enum EndReason { case completed, threshold, stopped }

    static let leadIn: Double = 10
    static var testLength: Double { leadIn + Chester.stageSeconds * 5 }

    // Settings
    @Published var age: Int? { didSet { saveSettings(); pushConfig() } }
    @Published var height: StepHeight { didSet { saveSettings() } }

    // Test state
    @Published var restHR: Int?
    @Published var stageHR: [Int?] = Array(repeating: nil, count: 5)
    @Published var autoFilled: Set<Int> = []
    @Published var liveHR: Int?
    @Published var phase: Phase = .setup
    @Published var elapsed: Double = 0
    @Published var endReason: EndReason?
    @Published var notice: String?
    @Published var watchStatus = "Checking for Apple Watch…"

    var maxHR: Int? { age.map { Chester.maxHR(age: $0) } }
    var stopHR: Int? { age.map { Chester.stopHR(age: $0) } }
    var result: Chester.Result? {
        guard let age else { return nil }
        return Chester.estimate(age: age, height: height, stageHR: stageHR)
    }

    /// 0-based stage currently being stepped, or nil during the lead-in.
    var stageIndex: Int? {
        let t = elapsed - Self.leadIn
        guard t >= 0 else { return nil }
        return min(4, Int(t / Chester.stageSeconds))
    }
    var secondsLeftInStage: Double {
        guard let s = stageIndex else { return max(0, Self.leadIn - elapsed) }
        return max(0, Self.leadIn + Double(s + 1) * Chester.stageSeconds - elapsed)
    }

    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speech = AVSpeechSynthesizer()
    private let sampleRate = 44100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var startDate: Date?
    private var timer: Timer?
    private var cues: [(time: Double, action: () -> Void)] = []
    private var nextCue = 0
    private var aboveCount = 0
    private var lastHRDate: Date?

    override init() {
        let d = UserDefaults.standard
        let savedAge = d.integer(forKey: "age")
        age = savedAge > 0 ? savedAge : nil
        height = StepHeight(rawValue: d.integer(forKey: "height")) ?? .cm30
        super.init()
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        } else {
            watchStatus = "Apple Watch not available"
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(age ?? 0, forKey: "age")
        UserDefaults.standard.set(height.rawValue, forKey: "height")
    }

    // MARK: - Running the test

    /// Starts the test. Returns an error message if it can't start.
    func start(restingHR: Int?) -> String? {
        guard phase != .running else { return "A test is already running." }
        guard let age, age >= 16, age <= 80 else { return "Enter your age on your iPhone first." }
        if let r = restingHR, r >= 100 {
            return "Starting heart rate \(r) is high. Rest for a few minutes and try again."
        }
        restHR = restingHR
        stageHR = Array(repeating: nil, count: 5)
        autoFilled = []
        endReason = nil
        notice = nil
        aboveCount = 0
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            try audioEngine.start()
        } catch {
            return "Couldn't start the audio: \(error.localizedDescription)"
        }
        scheduleBeats()
        buildCues()
        player.play()
        startDate = Date()
        elapsed = 0
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sendState()
        return nil
    }

    func finish(_ reason: EndReason) {
        guard phase == .running else { return }
        timer?.invalidate()
        timer = nil
        player.stop()
        audioEngine.stop()
        endReason = reason
        phase = .finished
        UIApplication.shared.isIdleTimerDisabled = false
        switch reason {
        case .threshold: say("Stop stepping. You've reached your target heart rate.")
        case .completed: say("Test complete. Stop stepping.")
        case .stopped: speech.stopSpeaking(at: .immediate)
        }
        sendResult()
    }

    func reset() {
        if phase == .running { finish(.stopped) }
        phase = .setup
        elapsed = 0
        stageHR = Array(repeating: nil, count: 5)
        autoFilled = []
        restHR = nil
        endReason = nil
        notice = nil
    }

    private func tick() {
        guard phase == .running, let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
        while nextCue < cues.count, cues[nextCue].time <= elapsed {
            let action = cues[nextCue].action
            nextCue += 1
            action()
            if phase != .running { return }
        }
    }

    private func stageEnded(_ i: Int) {
        if stageHR[i] == nil, let hr = liveHR, let last = lastHRDate, Date().timeIntervalSince(last) < 10 {
            stageHR[i] = hr
            autoFilled.insert(i)
        }
        if i == 4 { finish(.completed) }
    }

    // MARK: - Heart rate

    func handleHeartRate(_ hr: Int) {
        liveHR = hr
        lastHRDate = Date()
        guard phase == .running, let s = stageIndex, let stop = stopHR else { return }
        aboveCount = hr > stop ? aboveCount + 1 : 0
        if aboveCount >= 2 {   // two readings in a row, to ignore a single glitch
            stageHR[s] = max(stageHR[s] ?? 0, hr)
            autoFilled.remove(s)
            notice = "Your heart rate went over \(stop) bpm (80% of your max), so the test stopped in stage \(s + 1)."
            finish(.threshold)
        }
    }

    /// A Record HR press. In the first 15 seconds of a stage it belongs to the stage just finished.
    func record(_ hr: Int) -> String {
        guard phase == .running else { return "No test running" }
        guard let s = stageIndex else { return "Stage 1 hasn't started" }
        let intoStage = elapsed - Self.leadIn - Double(s) * Chester.stageSeconds
        let target = (intoStage < 15 && s > 0) ? s - 1 : s
        stageHR[target] = hr
        autoFilled.remove(target)
        let label = "Stage \(target + 1): \(hr) bpm"
        handleHeartRate(hr)
        return label
    }

    // MARK: - Audio

    private func tone(freq: Double, duration: Double, decay: Double, gain: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            data[i] = gain * Float(sin(2 * .pi * freq * t) * exp(-t * decay))
        }
        return buffer
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, at seconds: Double) {
        let when = AVAudioTime(sampleTime: AVAudioFramePosition(seconds * sampleRate), atRate: sampleRate)
        player.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
    }

    /// Up-up-down-down: four beats per step, the first of each step accented.
    private func scheduleBeats() {
        player.stop()
        let accent = tone(freq: 1500, duration: 0.07, decay: 55, gain: 0.9)
        let beat = tone(freq: 1000, duration: 0.07, decay: 55, gain: 0.65)
        let pip = tone(freq: 880, duration: 0.2, decay: 12, gain: 0.6)
        for t in [Self.leadIn - 3, Self.leadIn - 2, Self.leadIn - 1] { schedule(pip, at: t) }
        for (i, rate) in Chester.stepRates.enumerated() {
            let start = Self.leadIn + Double(i) * Chester.stageSeconds
            let interval = 60.0 / Double(rate * 4)
            let count = Int((Chester.stageSeconds / interval).rounded())
            for k in 0..<count {
                schedule(k % 4 == 0 ? accent : beat, at: start + Double(k) * interval)
            }
        }
    }

    private func buildCues() {
        let numbers = ["one", "two", "three", "four", "five"]
        let rates = ["fifteen", "twenty", "twenty five", "thirty", "thirty five"]
        cues = [(0, { [weak self] in
            self?.say("Get ready. Stage one, fifteen steps a minute. Start stepping on the beat.")
        })]
        for i in 0..<5 {
            let start = Self.leadIn + Double(i) * Chester.stageSeconds
            let end = start + Chester.stageSeconds
            cues.append((start + 0.1, { [weak self] in self?.sendState() }))
            if i > 0 {
                cues.append((start + 0.5, { [weak self] in
                    self?.say("Stage \(numbers[i]). \(rates[i]) steps a minute.")
                }))
            }
            cues.append((end - 15, { [weak self] in
                self?.say("Fifteen seconds. Get ready to record your heart rate.")
                self?.sendToWatch(["type": "prompt"], fallback: false)
            }))
            cues.append((end, { [weak self] in self?.stageEnded(i) }))
        }
        cues.sort { $0.time < $1.time }
        nextCue = 0
    }

    private func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        u.rate = 0.5
        speech.speak(u)
    }

    // MARK: - Apple Watch

    private var config: [String: Any] {
        var ctx: [String: Any] = ["ready": age != nil, "sent": Date().timeIntervalSince1970]
        if let maxHR, let stopHR { ctx["maxHR"] = maxHR; ctx["stopHR"] = stopHR }
        return ctx
    }

    func pushConfig() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(config)
        if s.isReachable {
            var msg = config
            msg["type"] = "config"
            s.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        }
    }

    private func sendToWatch(_ msg: [String: Any], fallback: Bool) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in
                if fallback { s.transferUserInfo(msg) }
            }
        } else if fallback {
            s.transferUserInfo(msg)
        }
    }

    private func sendState() {
        let label = stageIndex.map { "Stage \($0 + 1) · \(Chester.stepRates[$0])/min" } ?? "Get ready"
        sendToWatch(["type": "state", "label": label], fallback: false)
    }

    private func sendResult() {
        var msg: [String: Any] = ["type": "result", "reason": endReason == .threshold ? "threshold" : "done"]
        if let r = result { msg["vo2"] = r.vo2max }
        sendToWatch(msg, fallback: true)
    }

    fileprivate func updateWatchStatus() {
        let s = WCSession.default
        if !s.isPaired { watchStatus = "No Apple Watch paired" }
        else if !s.isWatchAppInstalled { watchStatus = "Install Fitness Test on your Apple Watch" }
        else if s.isReachable { watchStatus = "Apple Watch connected" }
        else { watchStatus = "Open Fitness Test on your Apple Watch" }
    }

    fileprivate func handle(_ m: [String: Any]) -> [String: Any] {
        let hr = m["hr"] as? Int
        switch m["type"] as? String {
        case "start":
            if let error = start(restingHR: hr) {
                notice = error
                return ["ok": false, "message": error]
            }
            return ["ok": true]
        case "hr":
            if let hr { handleHeartRate(hr) }
            return [:]
        case "record":
            guard let hr else { return ["message": "No heart rate"] }
            return ["message": record(hr)]
        case "stop":
            finish(.stopped)
            return ["ok": true]
        case "config":
            return config
        default:
            return [:]
        }
    }
}

extension TestEngine: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.updateWatchStatus()
            self.pushConfig()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.updateWatchStatus()
            self.pushConfig()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateWatchStatus() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handle(message)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in _ = self.handle(userInfo) }
    }
}
