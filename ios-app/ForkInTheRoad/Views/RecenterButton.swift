import SwiftUI
import MapKit

/// "Take me back to me" — shown over a map only once the camera has stopped
/// following the user, which is exactly when panning or pinching has moved it
/// away. MapKit's own `MapUserLocationButton` sits there permanently and reads
/// as just another chrome icon; this one is a piece of feedback: it appears
/// because the user did something, and disappears the moment it's been used.
struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Center on my location")
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }
}

extension MapCameraPosition {
    /// True once the camera is no longer pinned to the user — i.e. the user
    /// has dragged or zoomed the map. SwiftUI writes a plain `.camera`
    /// position back into the binding on any such gesture, so this flipping
    /// to false is the signal that they've taken manual control.
    var hasBeenMovedByUser: Bool { !followsUserLocation }
}
