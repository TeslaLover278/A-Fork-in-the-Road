import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: BanterSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Banter frequency") {
                    Picker("Frequency", selection: $settings.frequency) {
                        ForEach(BanterFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Voice characters") {
                    ForEach(VoicePersona.all) { persona in
                        Toggle(isOn: Binding(
                            get: { !settings.isMuted(persona) },
                            set: { _ in settings.toggleMute(persona) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(persona.displayName).font(.headline)
                                Text(persona.tagline)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Speech rate") {
                    Slider(value: $settings.speechRateMultiplier, in: 0.75...1.25, step: 0.05)
                    Text("Adjusts how fast both characters talk. Real turn-by-turn directions are unaffected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
