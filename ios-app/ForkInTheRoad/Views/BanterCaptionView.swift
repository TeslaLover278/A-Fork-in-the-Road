import SwiftUI

/// A small subtitle-style bubble showing which persona is "talking" and
/// what they're saying — lets banter be followed with sound off, and keeps
/// it visually distinct from the real turn banner above it.
struct BanterCaptionView: View {
    let personaID: String
    let text: String

    private var persona: VoicePersona? {
        VoicePersona.all.first { $0.id == personaID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String((persona?.displayName ?? "?").prefix(1)))
                .font(.system(.title3, design: .serif, weight: .black))
                .foregroundStyle(color)
                .frame(width: 36, height: 40)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(persona?.displayName.uppercased() ?? "PASSENGER") / ON AIR")
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(RoadTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .roadPanel()
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private var color: Color {
        switch personaID {
        case "dan": return RoadTheme.accent
        case "harry": return RoadTheme.teal
        default: return RoadTheme.muted
        }
    }
}
