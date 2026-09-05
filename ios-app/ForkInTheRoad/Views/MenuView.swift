import SwiftUI

/// The app's one settings surface, reachable from the home screen's menu
/// button and from the gear on the driving screen. Units live here directly
/// because they're a single choice; the longer voice/banter controls get
/// their own pushed page.
struct MenuView: View {
    @ObservedObject var banterSettings: BanterSettings
    @ObservedObject var unitSettings: UnitSettings
    @ObservedObject var speechQueue: SpeechQueueManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $unitSettings.preference) {
                        ForEach(UnitPreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Distance units")
                } footer: {
                    Text(unitsFooter)
                }

                Section {
                    NavigationLink {
                        SettingsView(settings: banterSettings, speechQueue: speechQueue)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voices & banter")
                                Text("Frequency, characters, speech rate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.wave.2.fill")
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Real turn-by-turn directions always come first — the characters only ever talk in the gaps, and are cut off the moment a real instruction is due.")
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var unitsFooter: String {
        let applies = "Applies to the turn banner, trip progress, and spoken directions."
        guard unitSettings.preference == .automatic else { return applies }
        let resolved = UnitSettings.deviceSystem == .metric ? "metric" : "imperial"
        return "Following your device region, which is \(resolved). \(applies)"
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
