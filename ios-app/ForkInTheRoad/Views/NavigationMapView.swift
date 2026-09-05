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
            MapUserLocationButton(scope: mapScope)
                .padding(.trailing, 16)
        }
    }
}
