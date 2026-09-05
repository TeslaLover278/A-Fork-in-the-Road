import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if let route = navigationEngine.route {
                MapPolyline(route.polyline)
                    .stroke(Color.accentColor, lineWidth: 6)
            }
        }
        .mapControls {
            MapUserLocationButton()
        }
    }
}
