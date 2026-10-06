import Foundation

/// Custom voice command: trigger phrase -> reply (at opsyonal na ESP32 action).
/// Parehong "||" variants ang gamit sa trigger at reply, tulad sa Android version.
struct VoiceCommand: Codable, Identifiable, Equatable {
    var trigger: String
    var reply: String
    var action: String = ""

    var id: String { trigger }

    func triggerVariants() -> [String] {
        trigger.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func randomReply() -> String {
        let variations = reply.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return variations.randomElement() ?? reply
    }
}

final class CommandStore: ObservableObject {
    @Published private(set) var commands: [VoiceCommand] = []

    private let commandsKey = "custom_commands_json"
    private let seededKey = "defaults_seeded_v1"
    private let store = UserDefaults.standard

    init() {
        load()
    }

    private func load() {
        guard let data = store.data(forKey: commandsKey),
              let decoded = try? JSONDecoder().decode([VoiceCommand].self, from: data) else {
            commands = []
            return
        }
        commands = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(commands) {
            store.set(data, forKey: commandsKey)
        }
    }

    func add(trigger: String, reply: String, action: String = "") {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanTrigger.isEmpty else { return }
        commands.removeAll { $0.trigger == cleanTrigger }
        commands.append(VoiceCommand(
            trigger: cleanTrigger,
            reply: reply.trimmingCharacters(in: .whitespacesAndNewlines),
            action: action.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        ))
        persist()
    }

    func remove(trigger: String) {
        commands.removeAll { $0.trigger == trigger }
        persist()
    }

    /// Isang beses lang tumatakbo - nilalagay ang mga default na utos mula sa Android app.
    func seedDefaultsIfNeeded() {
        if store.bool(forKey: seededKey) { return }

        let defaults: [VoiceCommand] = [
            VoiceCommand(trigger: "abante", reply: "ok sige", action: "FORWARD"),
            VoiceCommand(trigger: "saan ka papunta", reply: "wala akong pupuntahan paikot ikot lang ako dito", action: "RIGHT"),
            VoiceCommand(trigger: "sino ba si rasti", reply: "si rusty yung magaling na developer! nagtatrabaho sa globe. at nakatira sa pagbilao"),
            VoiceCommand(trigger: "sino si rasti", reply: "si rusty yung magaling na developer! nagtatrabaho sa globe. at nakatira sa pagbilao"),
            VoiceCommand(trigger: "ayaw ko nga", reply: "sige kung ayaw mo eh diwag"),
            VoiceCommand(trigger: "oo ang pangit", reply: "ikaw pangit din"),
            VoiceCommand(trigger: "nakaupo", reply: "sige upo ka lang diyan"),
            VoiceCommand(trigger: "mas pangit ka", reply: "eh di wow"),
            VoiceCommand(trigger: "ikaw saan papunta", reply: "ikot ikot lang", action: "LEFT"),
            VoiceCommand(trigger: "ikaw sa'n papunta", reply: "ikot lng ng ikot dito", action: "LEFT"),
            VoiceCommand(trigger: "ayaw ko", reply: "kung ayaw mo wag mo"),
            VoiceCommand(trigger: "ok lang", reply: "sige mabuti at ok lang"),
            VoiceCommand(trigger: "ikaw anong gawa mo", reply: "paikot ikot lang", action: "LEFT"),
            VoiceCommand(trigger: "anong gawa mo", reply: "ikot ikot lang", action: "LEFT"),
            VoiceCommand(trigger: "oo ang ganda", reply: "oo naman., pogi kasi ang gumawa sa akin", action: "FORWARD"),
            VoiceCommand(trigger: "sayaw", reply: "ok sige sasayaw ako.. wag ka tatawa ha!", action: "DANCE"),
            VoiceCommand(trigger: "ilang taon kana", reply: "wala akong edad pero kagagawa lang sa akin ni engineer rusty"),
            VoiceCommand(trigger: "saan ka galing", reply: "sa laboratoryo ni rusty"),
            VoiceCommand(trigger: "saan ka nakatira", reply: "nakatira ako sa laboratoryo ni rusty"),
            VoiceCommand(trigger: "oo kanina pa", reply: "sige, mabuti naman."),
            VoiceCommand(trigger: "paano ka ginawa", reply: "AKO AY BINUO SA LIKHANG ISIP NI RUSTY"),
            VoiceCommand(trigger: "nakakain ka ba ng pagkain", reply: "ayaw! ayaw! kuryente lang kinakain ko", action: "SHAKING"),
            VoiceCommand(trigger: "ikaw ba kumain na", reply: "hindi ako na kain", action: "SHAKING"),
            VoiceCommand(trigger: "power meter", reply: "OK! OK!"),
            VoiceCommand(trigger: "buksan ang laser", reply: "sige, binubuksan ko na", action: "LASER_ON"),
            VoiceCommand(trigger: "patayin ang laser", reply: "sige pinapatay ko na", action: "LASER_OFF"),
        ]

        for c in defaults {
            add(trigger: c.trigger, reply: c.reply, action: c.action)
        }
        store.set(true, forKey: seededKey)
    }

    /// Hinahanap ang command na may PINAKAMAHABANG trigger variant na nakapaloob sa sinabi ng user.
    func findMatch(_ spokenText: String) -> VoiceCommand? {
        var best: (length: Int, command: VoiceCommand)? = nil
        for cmd in commands {
            for variant in cmd.triggerVariants() where spokenText.contains(variant) {
                if best == nil || variant.count > best!.length {
                    best = (variant.count, cmd)
                }
            }
        }
        return best?.command
    }
}
