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
        .overlay(alignment: .bottomTrailing) {
            MapUserLocationButton(scope: mapScope)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
    }
}
