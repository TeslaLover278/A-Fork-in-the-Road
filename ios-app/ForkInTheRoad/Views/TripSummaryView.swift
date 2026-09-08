import SwiftUI

struct TripSummaryView: View {
    let destinationName: String
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 16) {
                    RoadMark()
                        .frame(width: 48, height: 56)
                    Text("A FORK IN THE ROAD\nTRIP RECEIPT")
                        .font(RoadTheme.eyebrow)
                        .foregroundStyle(RoadTheme.teal)
                        .fixedSize(horizontal: false, vertical: true)
                }

                receipt

                VStack(alignment: .leading, spacing: 16) {
                    Text("Every arrival is another starting point.")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onDone) {
                        Text("Pick another destination")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RoadButtonStyle())
                }
            }
            .frame(maxWidth: 640)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(RoadTheme.paper.ignoresSafeArea())
        .foregroundStyle(RoadTheme.ink)
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Label("END OF THIS ROAD", systemImage: "flag.checkered")
                    .font(RoadTheme.eyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You've arrived.")
                    .font(RoadTheme.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .foregroundStyle(RoadTheme.cream)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoadTheme.asphalt)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DESTINATION")
                        .font(RoadTheme.eyebrow)
                        .foregroundStyle(RoadTheme.teal)
                    Text(destinationName)
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                RoadRule()
                Text("The route was yours. So is the next one.")
                    .font(.body)
                    .foregroundStyle(RoadTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("UNTIL THE NEXT FORK")
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(RoadTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .roadPanel()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
