import SwiftUI

/// Bottom-sheet-style progress bar. Lives on top of the map and shows the
/// total remaining distance and estimated time to arrival. These values are
/// read straight from NavigationEngine so they stay in sync with the route.
struct TripProgressView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @ObservedObject var unitSettings: UnitSettings

    var body: some View {
        if navigationEngine.state == .navigating || navigationEngine.state == .rerouting {
            HStack(spacing: 0) {
                progressItem(title: "Distance", value: distanceLabel)
                Divider()
                progressItem(title: "ETA", value: etaLabel)
            }
            .padding(.vertical, 12)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: 80)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func progressItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
