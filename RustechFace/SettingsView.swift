import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var robot: RobotController
    @EnvironmentObject var settings: Settings
    @Environment(\.presentationMode) var presentation

    @State private var pingResult = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ESP32 Robot")) {
                    HStack {
                        Text("IP")
                        TextField("192.168.4.1", text: $settings.esp32Host)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    Button("Test Ping") {
                        pingResult = "Nagpi-ping..."
                        robot.pingNow { reply in
                            if let r = reply {
                                pingResult = "OK: \(r)"
                            } else {
                                pingResult = "Walang sagot. Check ang WiFi, IP, at Local Network permission."
                            }
                        }
                    }
                    if !pingResult.isEmpty {
                        Text(pingResult).font(.footnote).foregroundColor(.secondary)
                    }
                    Toggle("Baliktad ang kaliwa/kanan", isOn: $settings.flipLeftRight)
                    Toggle("Baliktad ang taas/baba (servo)", isOn: $settings.flipServo)
                }

                Section(header: Text("Face tracking")) {
                    Toggle("Ipakita ang camera (imbes na mata)", isOn: $settings.showCamera)
                    VStack(alignment: .leading) {
                        Text("Masyadong malapit (BACKWARD): \(String(format: "%.2f", settings.closeRatio))")
                        Slider(value: $settings.closeRatio, in: 0.20...0.80)
                    }
                    VStack(alignment: .leading) {
                        Text("Malayo na (FORWARD): \(String(format: "%.2f", settings.farRatio))")
                        Slider(value: $settings.farRatio, in: 0.05...0.60)
                    }
                    VStack(alignment: .leading) {
                        Text("Sobrang layo (STOP): \(String(format: "%.2f", settings.tooFarRatio))")
                        Slider(value: $settings.tooFarRatio, in: 0.02...0.40)
                    }
                }

                Section(header: Text("Boses")) {
                    Toggle("Mag-salita ang app (TTS)", isOn: $settings.appTtsEnabled)
                    Toggle("Gamitin ang ElevenLabs", isOn: $settings.elevenEnabled)
                    SecureField("ElevenLabs API key", text: $settings.elevenKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Voice ID", text: $settings.elevenVoiceId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("Test boses") {
                        robot.speak("Kumusta! Ako ang RUSTECH robot.")
                    }
                }

                Section(header: Text("Mga Utos at Log")) {
                    NavigationLink(destination: CommandsView().environmentObject(robot.commands)) {
                        Text("Mga Utos (\(robot.commands.commands.count))")
                    }
                    NavigationLink(destination: VoiceLogView().environmentObject(robot)) {
                        Text("Voice Log")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Sara") { presentation.wrappedValue.dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct CommandsView: View {
    @EnvironmentObject var commands: CommandStore

    @State private var trigger = ""
    @State private var reply = ""
    @State private var action = ""

    var body: some View {
        Form {
            Section(header: Text("Magdagdag / magpalit ng utos")) {
                TextField("Trigger (|| para sa variants)", text: $trigger)
                    .autocapitalization(.none)
                TextField("Reply (|| para sa random variants)", text: $reply)
                TextField("Action (FORWARD, LEFT, DANCE, dfplayer play 25)", text: $action)
                    .autocapitalization(.none)
                Button("Idagdag") {
                    commands.add(trigger: trigger, reply: reply, action: action)
                    trigger = ""
                    reply = ""
                    action = ""
                }
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section(header: Text("Mga utos (\(commands.commands.count))")) {
                ForEach(commands.commands) { cmd in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.trigger).font(.headline)
                        Text(cmd.reply).font(.subheadline).foregroundColor(.secondary)
                        if !cmd.action.isEmpty {
                            Text("Action: \(cmd.action)").font(.caption).foregroundColor(.blue)
                        }
                    }
                }
                .onDelete { offsets in
                    let victims = offsets.map { commands.commands[$0].trigger }
                    for t in victims { commands.remove(trigger: t) }
                }
            }
        }
        .navigationTitle("Mga Utos")
    }
}

struct VoiceLogView: View {
    @EnvironmentObject var robot: RobotController

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        List {
            if robot.voiceLog.isEmpty {
                Text("Wala pang narinig.").foregroundColor(.secondary)
            }
            ForEach(robot.voiceLog) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.timeFormatter.string(from: entry.time))  \(entry.heard)")
                        .font(.subheadline)
                    Text(entry.result).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Voice Log")
        .navigationBarItems(trailing: Button("Clear") { robot.voiceLog.removeAll() })
    }
}
