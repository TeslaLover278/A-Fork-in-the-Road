import SwiftUI

/// Bottom-sheet-style progress bar. Lives on top of the map and shows the
/// total remaining distance and estimated time to arrival. These values are
/// read straight from NavigationEngine so they stay in sync with the route.
struct TripProgressView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @ObservedObject var unitSettings: UnitSettings

    var body: some View {
        if navigationEngine.state == .navigating || navigationEngine.state == .rerouting {
            VStack(alignment: .leading, spacing: 12) {
                Text(navigationEngine.destinationName)
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(RoadTheme.muted)
                    .lineLimit(2)
                RoadRule()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        progressItem(title: "TO GO", value: distanceLabel)
                        progressItem(title: "DRIVE TIME", value: etaLabel)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) {
                        progressItem(title: "TO GO", value: distanceLabel)
                        progressItem(title: "DRIVE TIME", value: etaLabel)
                    }
                }
            }
            .padding(16)
            .roadPanel()
        }
    }

    private func progressItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(RoadTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(RoadTheme.eyebrow)
                .foregroundStyle(RoadTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var distanceLabel: String {
        unitSettings.shortDistance(navigationEngine.distanceRemainingTotal)
    }

    private var etaLabel: String {
        let minutes = navigationEngine.etaMinutes
        if minutes < 1 {
            return "< 1 min"
        } else if minutes < 60 {
            return "\(minutes) min"
        } else {
            return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
        }
    }
}
