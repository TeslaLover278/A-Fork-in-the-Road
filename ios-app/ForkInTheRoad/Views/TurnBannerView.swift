import SwiftUI

/// Always-on-top maneuver banner. This never reacts to banter state — it
/// only reflects NavigationEngine, which is the point: real directions are
/// never delayed or altered by the comedic layer.
struct TurnBannerView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @ObservedObject var unitSettings: UnitSettings

    var body: some View {
        if navigationEngine.state == .navigating || navigationEngine.state == .rerouting,
           let step = navigationEngine.steps[safe: navigationEngine.currentStepIndex] {
            HStack(spacing: 14) {
                Image(systemName: ManeuverIcon.symbolName(for: step.instructions))
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(distanceLabel)
                        .font(.headline)
                    Text(step.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    private var distanceLabel: String {
        unitSettings.shortDistance(navigationEngine.distanceToNextManeuver)
    }
}
