import Foundation
import AVFoundation
import Speech

struct LogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let heard: String
    let result: String
}

/// Utak ng app - kinokonekta ang camera, mata, ESP32, boses, at mga command.
/// Lahat ng trabaho dito ay nasa main thread.
final class RobotController: ObservableObject {

    let settings: Settings
    let commands: CommandStore
    let camera: CameraService
    let esp: Esp32Client
    let speaker: Speaker
    let listener: SpeechListener

    @Published var mood: EyeMood = .idle
    @Published var statusText: String = "Handa na"
    @Published var espOnline: Bool = false
    @Published var voiceLog: [LogEntry] = []

    private var started = false
    private var pingTimer: Timer?

    // Face tracking state
    private var lastPersonSeen = Date.distantPast
    private var faceTooClose = false
    private let personTimeout: TimeInterval = 4.0
    private var lastStopSent = Date.distantPast

    // Servo (step-and-settle, port ng computeServoAngle sa Android)
    private let servoMaxAngle: Float = 110
    private var outputServoAngle: Float = -1
    private var lastServoStep = Date.distantPast
    private let servoTargetRatio: Float = 0.5
    private let servoCameraFovDeg: Float = 45
    private let servoStepGain: Float = 0.65
    private let servoMaxStepDeg: Float = 10
    private let servoDeadbandRatio: Float = 0.06
    private let servoStepInterval: TimeInterval = 0.25

    // Voice-driven na galaw
    private var voiceOverrideActive = false
    private var timedTimer: Timer?
    private let voiceMovementDuration: TimeInterval = 3.0
    private let movementActions: Set<String> = ["FORWARD", "BACKWARD", "LEFT", "RIGHT"]

    init() {
        let s = Settings()
        settings = s
        commands = CommandStore()
        camera = CameraService()
        esp = Esp32Client(settings: s)
        speaker = Speaker(settings: s)
        listener = SpeechListener()

        commands.seedDefaultsIfNeeded()

        camera.onFace = { [weak self] rect in self?.handleFace(rect) }
        speaker.onSpeakingChanged = { [weak self] speaking in self?.speakingChanged(speaking) }
        speaker.onLog = { [weak self] a, b in self?.addLog(a, b) }
        listener.onUtterance = { [weak self] text in self?.handleUtterance(text) }
        listener.onStatus = { [weak self] text in self?.setStatus(text) }
    }

    // MARK: - Startup

    func start() {
        guard !started else { return }
        started = true

        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? audio.setActive(true)

        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.camera.start()
                } else {
                    self.setStatus("Walang camera permission - i-on sa Settings > RUSTECH Face")
                }
            }
        }

        SFSpeechRecognizer.requestAuthorization { speechStatus in
            audio.requestRecordPermission { micOK in
                DispatchQueue.main.async {
                    if speechStatus == .authorized && micOK {
                        self.listener.start()
                    } else {
                        self.setStatus("Walang mic/speech permission - i-on sa Settings > RUSTECH Face")
                    }
                }
            }
        }

        pingNow { [weak self] reply in
            self?.espOnline = (reply != nil)
        }
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.esp.ping { reply in
                self?.espOnline = (reply != nil)
            }
        }
    }

    func pingNow(done: @escaping (String?) -> Void) {
        esp.ping(done: done)
    }

    // MARK: - Helpers

    private func setStatus(_ text: String) {
        if statusText != text { statusText = text }
    }

    private func setMood(_ new: EyeMood) {
        if mood != new { mood = new }
    }

    func addLog(_ heard: String, _ result: String) {
        voiceLog.insert(LogEntry(heard: heard, result: result), at: 0)
        if voiceLog.count > 300 { voiceLog.removeLast(voiceLog.count - 300) }
    }

    func speak(_ text: String) {
        speaker.speak(text)
    }

    private func speakingChanged(_ speaking: Bool) {
        if speaking { listener.pause() } else { listener.resume() }
    }

    // MARK: - Face tracking

    private func handleFace(_ rect: CGRect?) {
        guard let r = rect else {
            handleNoFace()
            return
        }

        lastPersonSeen = Date()

        let widthRatio = Float(r.width)
        let close = Float(settings.closeRatio)
        if !faceTooClose && widthRatio > close {
            faceTooClose = true
        } else if faceTooClose && widthRatio < close * 0.9 {
            faceTooClose = false
        }
        setMood(faceTooClose ? .angry : .alert)
        setStatus("May Tao")

        let command = computeCommand(r)
        let servo = computeServoAngle(r)
        if !voiceOverrideActive {
            esp.sendTracking(dir: command, servo: servo)
        }
    }

    private func handleNoFace() {
        let now = Date()
        if !voiceOverrideActive && now.timeIntervalSince(lastStopSent) > 1.5 {
            lastStopSent = now
            esp.sendTracking(dir: "STOP", servo: nil)
        }
        if now.timeIntervalSince(lastPersonSeen) > personTimeout {
            setMood(.idle)
            setStatus("Handa na")
        } else {
            setMood(.searching)
        }
    }

    private func computeCommand(_ r: CGRect) -> String {
        let w = Float(r.width)
        if w > Float(settings.closeRatio) { return "BACKWARD" }

        let cx = Float(r.midX)
        let dead: Float = 1.0 / 3.5 / 2.0
        let leftBoundary = 0.5 - dead
        let rightBoundary = 0.5 + dead

        var cmd: String
        if cx < leftBoundary {
            cmd = "RIGHT"
        } else if cx > rightBoundary {
            cmd = "LEFT"
        } else if w < Float(settings.tooFarRatio) {
            cmd = "STOP"
        } else if w < Float(settings.farRatio) {
            cmd = "FORWARD"
        } else {
            cmd = "STOP"
        }

        if settings.flipLeftRight {
            if cmd == "LEFT" { cmd = "RIGHT" } else if cmd == "RIGHT" { cmd = "LEFT" }
        }
        return cmd
    }

    private func computeServoAngle(_ r: CGRect) -> Int {
        let verticalRatio = Float(r.midY) // top-left origin na
        if outputServoAngle < 0 { outputServoAngle = servoMaxAngle / 2 }

        let now = Date()
        if now.timeIntervalSince(lastServoStep) >= servoStepInterval {
            lastServoStep = now
            let error = servoTargetRatio - verticalRatio
            if abs(error) > servoDeadbandRatio {
                let direction: Float = settings.flipServo ? -1 : 1
                let errorDeg = error * servoCameraFovDeg * direction
                let step = min(max(errorDeg * servoStepGain, -servoMaxStepDeg), servoMaxStepDeg)
                outputServoAngle = min(max(outputServoAngle + step, 0), servoMaxAngle)
            }
        }
        return Int(outputServoAngle.rounded())
    }

    // MARK: - Voice commands

    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "'" }
        return allowed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleUtterance(_ raw: String) {
        let heard = normalize(raw)
        guard !heard.isEmpty else { return }

        // Hinto / stop / tigil -> FORCE_STOP agad
        if ["hinto", "stop", "tigil"].contains(where: { heard.contains($0) }) {
            timedTimer?.invalidate()
            voiceOverrideActive = false
            esp.send(dir: "FORCE_STOP")
            addLog(raw, "FORCE_STOP")
            return
        }

        if let cmd = commands.findMatch(heard) {
            addLog(raw, "tugma: \(cmd.trigger)" + (cmd.action.isEmpty ? "" : " -> \(cmd.action)"))
            if !cmd.action.isEmpty { executeActions(cmd.action) }
            speak(cmd.randomReply())
        } else {
            addLog(raw, "walang tugma")
        }
    }

    // MARK: - ESP32 actions ("||"-separated, may "dfplayer play N")

    private func dfPlayerTrack(_ part: String) -> Int? {
        guard let range = part.range(of: #"dfplayer\s+play\s+\d+"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let digits = String(part[range]).filter { $0.isNumber }
        return Int(digits)
    }

    func executeActions(_ field: String) {
        let parts = field.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var tracks: [Int] = []
        var others: [String] = []
        for p in parts {
            if let t = dfPlayerTrack(p) { tracks.append(t) } else { others.append(p) }
        }

        if let first = tracks.first {
            // Hintayin munang sumagot ang ESP32 sa DFPlayer bago ang movement
            esp.play(track: first) { [weak self] reply in
                if reply == nil || reply!.code != 200 {
                    self?.addLog("DFPlayer track \(first)", reply == nil ? "HTTP FAILED" : "HTTP \(reply!.code)")
                }
                self?.runMovement(others)
            }
            for t in tracks.dropFirst() { esp.play(track: t) }
        } else {
            runMovement(others)
        }
    }

    private func runMovement(_ parts: [String]) {
        guard let first = parts.first else { return }
        let rest = Array(parts.dropFirst())
        let upper = first.uppercased()

        if movementActions.contains(upper) {
            sendTimed(upper, duration: voiceMovementDuration) { [weak self] in
                self?.runMovement(rest)
            }
        } else {
            esp.send(dir: upper == "STOP" ? "FORCE_STOP" : first)
            runMovement(rest)
        }
    }

    /// Uulit-ulitin ang movement command kada 300ms hanggang matapos ang duration, tapos STOP.
    private func sendTimed(_ command: String, duration: TimeInterval, completion: @escaping () -> Void) {
        voiceOverrideActive = true
        timedTimer?.invalidate()
        let end = Date().addingTimeInterval(duration)
        esp.send(dir: command)
        timedTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if Date() < end {
                self.esp.send(dir: command)
            } else {
                timer.invalidate()
                self.esp.send(dir: "STOP")
                self.voiceOverrideActive = false
                completion()
            }
        }
    }
}
