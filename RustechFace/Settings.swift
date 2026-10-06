import Foundation

/// Mga setting ng app (naka-save sa UserDefaults, parang SharedPreferences sa Android).
final class Settings: ObservableObject {
    static let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM" // "Rachel" - pre-made voice ng ElevenLabs

    private let store = UserDefaults.standard

    @Published var esp32Host: String { didSet { store.set(esp32Host, forKey: "esp32_host") } }
    @Published var appTtsEnabled: Bool { didSet { store.set(appTtsEnabled, forKey: "app_tts_enabled") } }
    @Published var elevenEnabled: Bool { didSet { store.set(elevenEnabled, forKey: "elevenlabs_enabled") } }
    @Published var elevenKey: String { didSet { store.set(elevenKey, forKey: "elevenlabs_api_key") } }
    @Published var elevenVoiceId: String { didSet { store.set(elevenVoiceId, forKey: "elevenlabs_voice_id") } }
    @Published var showCamera: Bool { didSet { store.set(showCamera, forKey: "show_camera") } }
    @Published var flipLeftRight: Bool { didSet { store.set(flipLeftRight, forKey: "flip_lr") } }
    @Published var flipServo: Bool { didSet { store.set(flipServo, forKey: "flip_servo") } }
    @Published var closeRatio: Double { didSet { store.set(closeRatio, forKey: "close_face_ratio") } }
    @Published var farRatio: Double { didSet { store.set(farRatio, forKey: "far_face_ratio") } }
    @Published var tooFarRatio: Double { didSet { store.set(tooFarRatio, forKey: "too_far_face_ratio") } }

    init() {
        let d = UserDefaults.standard
        esp32Host = d.string(forKey: "esp32_host") ?? "192.168.4.1"
        appTtsEnabled = d.object(forKey: "app_tts_enabled") as? Bool ?? true
        elevenEnabled = d.object(forKey: "elevenlabs_enabled") as? Bool ?? false
        elevenKey = d.string(forKey: "elevenlabs_api_key") ?? ""
        elevenVoiceId = d.string(forKey: "elevenlabs_voice_id") ?? Settings.defaultVoiceId
        showCamera = d.object(forKey: "show_camera") as? Bool ?? false
        flipLeftRight = d.object(forKey: "flip_lr") as? Bool ?? false
        flipServo = d.object(forKey: "flip_servo") as? Bool ?? false
        closeRatio = d.object(forKey: "close_face_ratio") as? Double ?? 0.40
        farRatio = d.object(forKey: "far_face_ratio") as? Double ?? 0.23
        tooFarRatio = d.object(forKey: "too_far_face_ratio") as? Double ?? 0.15
    }

    /// "192.168.4.1" -> "http://192.168.4.1"
    var baseURL: String {
        var h = esp32Host.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("http://") { h = String(h.dropFirst(7)) }
        while h.hasSuffix("/") { h.removeLast() }
        return "http://" + h
    }
}
