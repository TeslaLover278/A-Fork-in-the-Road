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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Text("THE GLOVEBOX")
                                .font(RoadTheme.eyebrow)
                                .foregroundStyle(RoadTheme.teal)
                            Spacer(minLength: 12)
                            RoadMark()
                                .frame(width: 48, height: 56)
                                .accessibilityHidden(true)
                        }
                        Text("Make it your road.")
                            .font(RoadTheme.title)
                            .accessibilityAddTraits(.isHeader)
                        Text("A few adjustments before the next fork.")
                            .foregroundStyle(RoadTheme.muted)
                        RoadRule()
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("01 / DISTANCE UNITS")
                            .font(RoadTheme.eyebrow)
                            .foregroundStyle(RoadTheme.teal)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 8) {
                            ForEach(UnitPreference.allCases) { preference in
                                unitChoice(preference)
                            }
                        }
                        Text(unitsFooter)
                            .font(.footnote)
                            .foregroundStyle(RoadTheme.muted)
                    }
                    .padding(20)
                    .roadPanel()

                    NavigationLink {
                        SettingsView(settings: banterSettings, speechQueue: speechQueue)
                    } label: {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("02 / YOUR TRAVEL COMPANIONS")
                                    .font(RoadTheme.eyebrow)
                                    .foregroundStyle(RoadTheme.teal)
                                Text("Voices & banter")
                                    .font(.system(.title2, design: .serif, weight: .bold))
                                    .foregroundStyle(RoadTheme.ink)
                                Text("Frequency, characters, speech rate")
                                    .font(.subheadline)
                                    .foregroundStyle(RoadTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(RoadTheme.accent)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .roadPanel()
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("03 / ABOUT THIS TRIP")
                            .font(RoadTheme.eyebrow)
                            .foregroundStyle(RoadTheme.teal)
                            .accessibilityAddTraits(.isHeader)
                        Text("A Fork in the Road")
                            .font(.system(.title3, design: .serif, weight: .bold))
                        Text("Version \(appVersion)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(RoadTheme.muted)
                        RoadRule()
                            .accessibilityHidden(true)
                        Text("By default, Dan and Harry call out your turns themselves — a plain, literal voice is one toggle away in Voices & Banter. Either way, a rerouting or arrival announcement always cuts them off immediately.")
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
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RoadTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(RoadTheme.accent)
                }
            }
        }
        .tint(RoadTheme.accent)
    }

    private func unitChoice(_ preference: UnitPreference) -> some View {
        let selected = unitSettings.preference == preference
        return Button {
            unitSettings.preference = preference
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preference.displayName)
                        .font(.headline)
                    Text(unitDetail(preference))
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
        .accessibilityHint("Sets distance units for the trip and spoken directions")
    }

    private func unitDetail(_ preference: UnitPreference) -> String {
        switch preference {
        case .automatic: return "Follow your device region"
        case .metric: return "Kilometres & metres"
        case .imperial: return "Miles & feet"
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
