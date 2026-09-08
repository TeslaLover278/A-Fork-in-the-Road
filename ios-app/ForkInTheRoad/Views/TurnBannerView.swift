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
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: ManeuverIcon.symbolName(for: step.instructions))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(RoadTheme.asphalt)
                    .frame(width: 60, height: 64)
                    .background(RoadTheme.cream, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(navigationEngine.state == .rerouting ? "REROUTING" : "NEXT TURN")
                        .font(RoadTheme.eyebrow)
                    Text(distanceLabel)
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                    Text(step.instructions)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(RoadTheme.cream)
            .padding(16)
            .background(RoadTheme.asphalt, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(RoadTheme.cream.opacity(0.4), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var distanceLabel: String {
        unitSettings.shortDistance(navigationEngine.distanceToNextManeuver)
    }
}
