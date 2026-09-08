import SwiftUI

/// Voice and banter controls. This is a pushed page inside `MenuView`, not a
/// sheet of its own, so it deliberately brings no NavigationStack or Done
/// button with it.
struct SettingsView: View {
    @ObservedObject var settings: BanterSettings
    @ObservedObject var speechQueue: SpeechQueueManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("THE ON-BOARD COMPANY")
                        .font(RoadTheme.eyebrow)
                        .foregroundStyle(RoadTheme.teal)
                    Text("Good roads.\nQuestionable company.")
                        .font(RoadTheme.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("Set the tone with Dan and Harry.")
                        .foregroundStyle(RoadTheme.muted)
                    RoadRule()
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionHeading("01 / TURN BY TURN")
                    Toggle("Real directions", isOn: $settings.realDirectionsEnabled)
                        .font(.headline)
                    Text(settings.realDirectionsEnabled
                         ? "Turns are read out in a plain voice, like a normal maps app."
                         : "Turns are delivered by Dan and Harry instead of a plain voice — Dan calls out the turn, Harry disagrees with him about it. Turn this on for a plain, literal voice instead.")
                        .font(.footnote)
                        .foregroundStyle(RoadTheme.muted)
                }
                .padding(20)
                .roadPanel()

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeading("02 / BANTER FREQUENCY")
                    Text("How much company?")
                        .font(.system(.title2, design: .serif, weight: .bold))
                    VStack(spacing: 8) {
                        ForEach(BanterFrequency.allCases) { frequency in
                            frequencyChoice(frequency)
                        }
                    }
                }
                .padding(20)
                .roadPanel()

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeading("03 / VOICE CHARACTERS")
                    ForEach(VoicePersona.all) { persona in
                        PersonaRow(
                            persona: persona,
                            isOn: !settings.isMuted(persona),
                            isSpeaking: speechQueue.activePersonaID == persona.id,
                            onToggle: { settings.toggleMute(persona) },
                            onPreview: { preview(persona) }
                        )
                    }
                    if VoiceCatalog.shared.allVoicesAreBasicQuality() {
                        // The single biggest win available on the voices, and
                        // nothing the app can do for the user itself — the
                        // downloads live behind an Accessibility screen with
                        // no public URL to deep-link to.
                        Text("Both characters are using basic system voices. For much better ones, download an Enhanced or Premium English voice in Settings › Accessibility › Spoken Content › Voices, then come back here.")
                            .font(.footnote)
                            .foregroundStyle(RoadTheme.muted)
                            .padding(16)
                            .roadPanel()
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionHeading("04 / SPEECH RATE")
                    Text("\(settings.speechRateMultiplier, specifier: "%.2f")× pace")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundStyle(RoadTheme.accent)
                        .accessibilityHidden(true)
                    Slider(value: $settings.speechRateMultiplier, in: 0.75...1.25, step: 0.05) {
                        Text("Speech rate")
                    }
                    .accessibilityValue("\(settings.speechRateMultiplier, specifier: "%.2f") times normal speed")
                    HStack {
                        Text("SLOWER")
                        Spacer()
                        Text("FASTER")
                    }
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(RoadTheme.muted)
                    .accessibilityHidden(true)
                    Text("Adjusts how fast both characters talk, including when they're calling out a turn. The plain voice used when Real Directions is on is unaffected.")
                        .font(.footnote)
                        .foregroundStyle(RoadTheme.muted)
                }
                .padding(20)
                .roadPanel()

                VStack(alignment: .leading, spacing: 14) {
                    sectionHeading("05 / ON-SCREEN CAPTIONS")
                    Toggle("Show captions", isOn: $settings.showCaptions)
                        .font(.headline)
                    Text("Shows banter as on-screen subtitles while it's being spoken.")
                        .font(.footnote)
                        .foregroundStyle(RoadTheme.muted)
                }
                .padding(20)
                .roadPanel()
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(RoadTheme.paper)
        .foregroundStyle(RoadTheme.ink)
        .tint(RoadTheme.teal)
        .navigationTitle("Voices & Banter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RoadTheme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onDisappear { speechQueue.stopAllBanter() }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(RoadTheme.eyebrow)
            .foregroundStyle(RoadTheme.teal)
            .accessibilityAddTraits(.isHeader)
    }

    private func frequencyChoice(_ frequency: BanterFrequency) -> some View {
        let selected = settings.frequency == frequency
        return Button {
            settings.frequency = frequency
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(frequency.displayName)
                        .font(.headline)
                    Text(frequencyDetail(frequency))
                        .font(.caption)
                        .foregroundStyle(RoadTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? RoadTheme.accent : RoadTheme.muted)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(RoadTheme.ink)
            .padding(14)
            .frame(minHeight: 56)
            .background(selected ? RoadTheme.accent.opacity(0.08) : RoadTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? RoadTheme.accent : RoadTheme.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Sets how often your companions talk")
    }

    private func frequencyDetail(_ frequency: BanterFrequency) -> String {
        switch frequency {
        case .off: return "Just the directions. A little peace and quiet."
        case .occasional: return "A few words along the way."
        case .chatty: return "More back-and-forth from the passenger seats."
        }
    }

    /// Previews go through the same banter lane as everything else, so a real
    /// instruction still cuts a preview off mid-word if one arrives while
    /// Settings is open mid-drive.
    private func preview(_ persona: VoicePersona) {
        speechQueue.stopAllBanter()
        speechQueue.enqueueBanter(SpeechRequest(
            content: .text(persona.previewLine),
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
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { isOn }, set: { _ in onToggle() })) {
                Text(persona.displayName)
                    .font(.system(.title2, design: .serif, weight: .bold))
            }
            .accessibilityHint("Turns this character's banter on or off")

            Text(persona.tagline)
                .font(.subheadline)
                .foregroundStyle(RoadTheme.muted)

            RoadRule()
                .accessibilityHidden(true)

            Text(VoiceCatalog.shared.description(for: persona))
                .font(.footnote.monospaced())
                .foregroundStyle(RoadTheme.muted)

            Button(action: onPreview) {
                Label(isSpeaking ? "Playing" : "Preview voice", systemImage: isSpeaking ? "waveform" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RoadButtonStyle(secondary: true))
            .disabled(isSpeaking)
            .accessibilityLabel("\(isSpeaking ? "Playing" : "Preview") \(persona.displayName)")
        }
        .padding(20)
        .roadPanel()
    }
}
