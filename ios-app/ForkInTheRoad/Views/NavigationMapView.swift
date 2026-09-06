import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Namespace private var mapScope

    var body: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            UserAnnotation()
            if let route = navigationEngine.route {
                MapPolyline(route.polyline)
                    .stroke(Color.accentColor, lineWidth: 6)
            }
        }
        .mapScope(mapScope)
        // Mid-trailing edge: the turn banner (top), banter caption, and
        // TripProgressView (bottom) are all full-width and vary in height,
        // so any fixed top/bottom offset risks getting covered by one of them.
        .overlay(alignment: .trailing) {
            if cameraPosition.hasBeenMovedByUser {
                RecenterButton(action: recenter)
                    .padding(.trailing, 16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameraPosition.hasBeenMovedByUser)
    }

    /// Hands the camera back to MapKit's user-location tracking. Mid-drive
    /// this matters more than on the home map — glancing away from the road
    /// to drag the map back is the thing we're trying to avoid.
    private func recenter() {
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .userLocation(fallback: .automatic)
        }
    }
}
