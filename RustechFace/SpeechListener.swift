import Foundation
import Speech
import AVFoundation

/// Voice input gamit ang Apple Speech framework (fil-PH, fallback en-PH/en-US).
/// Tuloy-tuloy na nakikinig; kapag natahimik ng ~1.2s, ibibigay ang buong narinig bilang isang "utterance".
/// Lahat ng callback ay sa main thread.
final class SpeechListener {

    var onUtterance: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var silenceTimer: Timer?
    private var lastText = ""
    private var generation = 0
    private var running = false
    private var paused = false
    private var tapInstalled = false
    private var lastLocaleUsed = ""

    func start() {
        guard !running else { return }
        running = true
        paused = false
        beginListening()
    }

    func pause() {
        paused = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        generation += 1
        task?.cancel()
        task = nil
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()
        lastText = ""
        stopEngine()
    }

    func resume() {
        guard running else { return }
        paused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.beginListening()
        }
    }

    // MARK: - Internals

    private func pickRecognizer() -> SFSpeechRecognizer? {
        for code in ["fil-PH", "en-PH", "en-US"] {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: code)), r.isAvailable {
                if code != lastLocaleUsed {
                    lastLocaleUsed = code
                    onStatus?("Mic: nakikinig sa \(code)")
                }
                return r
            }
        }
        return nil
    }

    private func beginListening() {
        guard running, !paused, task == nil else { return }
        guard let recognizer = pickRecognizer() else {
            onStatus?("Walang speech recognizer (kailangan ng internet?)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.beginListening() }
            return
        }

        generation += 1
        let gen = generation

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        lock.lock(); request = req; lock.unlock()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                if let result = result {
                    self.lastText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishUtterance()
                    } else {
                        self.armSilenceTimer()
                    }
                } else if error != nil {
                    self.finishUtterance()
                }
            }
        }

        startEngineIfNeeded()
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.finishUtterance()
        }
    }

    private func finishUtterance() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = ""

        generation += 1 // ibasura ang mga susunod na callback ng lumang task
        task?.cancel()
        task = nil
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()

        if !text.isEmpty { onUtterance?(text) }

        let delay: TimeInterval = text.isEmpty ? 1.0 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginListening()
        }
    }

    private func startEngineIfNeeded() {
        if !tapInstalled {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                onStatus?("Mic: hindi pa handa ang audio input")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.lock.lock()
                let req = self.request
                self.lock.unlock()
                req?.append(buffer)
            }
            tapInstalled = true
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                onStatus?("Audio engine error: \(error.localizedDescription)")
            }
        }
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }
}
