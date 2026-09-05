import SwiftUI

struct TripSummaryView: View {
    let destinationName: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "flag.checkered.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You've arrived")
                .font(.largeTitle.bold())
            Text(destinationName)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
}
