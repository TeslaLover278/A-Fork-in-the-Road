import SwiftUI

/// Voice and banter controls. This is a pushed page inside `MenuView`, not a
/// sheet of its own, so it deliberately brings no NavigationStack or Done
/// button with it.
struct SettingsView: View {
    @ObservedObject var settings: BanterSettings
    @ObservedObject var speechQueue: SpeechQueueManager

    var body: some View {
        Form {
            Section {
                Toggle("Real directions", isOn: $settings.realDirectionsEnabled)
            } footer: {
                Text(settings.realDirectionsEnabled
                     ? "Turns are read out in a plain voice, like a normal maps app."
                     : "Turns are delivered by Dez and Vale instead of a plain voice — Dez calls out the turn, Vale disagrees with him about it. Turn this on for a plain, literal voice instead.")
            }

            Section("Banter frequency") {
                Picker("Frequency", selection: $settings.frequency) {
                    ForEach(BanterFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(VoicePersona.all) { persona in
                    PersonaRow(
                        persona: persona,
                        isOn: !settings.isMuted(persona),
                        isSpeaking: speechQueue.activePersonaID == persona.id,
                        onToggle: { settings.toggleMute(persona) },
                        onPreview: { preview(persona) }
                    )
                }
            } header: {
                Text("Voice characters")
            } footer: {
                if VoiceCatalog.shared.allVoicesAreBasicQuality() {
                    // The single biggest win available on the voices, and
                    // nothing the app can do for the user itself — the
                    // downloads live behind an Accessibility screen with
                    // no public URL to deep-link to.
                    Text("Both characters are using basic system voices. For much better ones, download an Enhanced or Premium English voice in Settings › Accessibility › Spoken Content › Voices, then come back here.")
                }
            }

            Section("Speech rate") {
                Slider(value: $settings.speechRateMultiplier, in: 0.75...1.25, step: 0.05)
                Text("Adjusts how fast both characters talk, including when they're calling out a turn. The plain voice used when Real Directions is on is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show captions", isOn: $settings.showCaptions)
            } footer: {
                Text("Shows banter as on-screen subtitles while it's being spoken.")
            }
        }
        .navigationTitle("Voices & Banter")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speechQueue.stopAllBanter() }
    }

    /// Previews go through the same banter lane as everything else, so a real
    /// instruction still cuts a preview off mid-word if one arrives while
    /// Settings is open mid-drive.
    private func preview(_ persona: VoicePersona) {
        speechQueue.stopAllBanter()
        speechQueue.enqueueBanter(SpeechRequest(
            text: persona.previewLine,
            persona: persona,
            rateMultiplier: settings.speechRateMultiplier,
            onStart: nil,
            onFinish: nil
        ))
    }
}

private struct PersonaRow: View {
    let persona: VoicePersona
    let isOn: Bool
    let isSpeaking: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { isOn }, set: { _ in onToggle() })) {
                Text(persona.displayName).font(.headline)
            }

            Text(persona.tagline)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(VoiceCatalog.shared.description(for: persona))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: onPreview) {
                    Label(isSpeaking ? "Playing" : "Preview", systemImage: isSpeaking ? "waveform" : "play.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSpeaking)
            }
        }
        .padding(.vertical, 2)
    }
}
