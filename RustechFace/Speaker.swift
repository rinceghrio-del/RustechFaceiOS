import Foundation
import AVFoundation

/// TTS: ElevenLabs (kung naka-ON at may API key) na may awtomatikong fallback sa lokal na
/// iOS TTS (AVSpeechSynthesizer, fil-PH kung meron). Lahat ng method ay tinatawag sa main thread.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    var onSpeakingChanged: ((Bool) -> Void)?
    var onLog: ((String, String) -> Void)?

    private let settings: Settings
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?
    private var elevenPending = false
    private var speaking = false
    private var token = 0

    init(settings: Settings) {
        self.settings = settings
        super.init()
        synth.delegate = self
    }

    // MARK: - Public

    func speak(_ phrase: String) {
        guard settings.appTtsEnabled else { return }
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        stopAll()
        token += 1

        let key = settings.elevenKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.elevenEnabled && !key.isEmpty {
            speakEleven(clean, apiKey: key, token: token)
        } else {
            speakLocal(clean)
        }
    }

    // MARK: - Internals

    private func stopAll() {
        elevenPending = false
        currentUtterance = nil
        synth.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        refreshSpeakingState()
    }

    private func refreshSpeakingState() {
        let now = (currentUtterance != nil) || elevenPending || (player != nil)
        if now != speaking {
            speaking = now
            onSpeakingChanged?(now)
        }
    }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        for code in ["fil-PH", "en-PH", "en-US"] {
            if let v = AVSpeechSynthesisVoice(language: code) { return v }
        }
        return nil
    }

    private func speakLocal(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = pickVoice()
        utterance.volume = 1.0
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance
        refreshSpeakingState()
        synth.speak(utterance)
    }

    private func speakEleven(_ text: String, apiKey: String, token t: Int) {
        elevenPending = true
        refreshSpeakingState()

        let trimmedVoice = settings.elevenVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = trimmedVoice.isEmpty ? Settings.defaultVoiceId : trimmedVoice

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)") else {
            elevenPending = false
            onLog?("ElevenLabs TTS", "Mali ang voice ID - fallback sa lokal na TTS")
            speakLocal(text)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, t == self.token else { return }
                self.elevenPending = false

                if let error = error {
                    self.onLog?("ElevenLabs TTS", "HTTP FAILED: \(error.localizedDescription) - fallback sa lokal na TTS")
                    self.speakLocal(text)
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data = data, !data.isEmpty else {
                    self.onLog?("ElevenLabs TTS", "HTTP \(code) - fallback sa lokal na TTS")
                    self.speakLocal(text)
                    return
                }
                do {
                    let p = try AVAudioPlayer(data: data)
                    p.delegate = self
                    p.volume = 1.0
                    p.prepareToPlay()
                    self.player = p
                    p.play()
                    self.refreshSpeakingState()
                } catch {
                    self.onLog?("ElevenLabs TTS", "Playback error: \(error.localizedDescription) - fallback sa lokal na TTS")
                    self.speakLocal(text)
                }
            }
        }.resume()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if utterance === self.currentUtterance { self.currentUtterance = nil }
            self.refreshSpeakingState()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if utterance === self.currentUtterance { self.currentUtterance = nil }
            self.refreshSpeakingState()
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            if p === self.player { self.player = nil }
            self.refreshSpeakingState()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            if p === self.player { self.player = nil }
            self.refreshSpeakingState()
        }
    }
}
