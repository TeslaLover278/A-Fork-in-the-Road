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
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(persona?.displayName ?? "???")
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text(text)
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: text)
    }

    private var color: Color {
        switch personaID {
        case "dan": return .orange
        case "harry": return .purple
        default: return .gray
        }
    }
}
