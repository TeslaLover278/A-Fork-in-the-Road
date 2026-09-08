import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var navigationEngine: NavigationEngine
    /// Owned by NavigationScreen so the recenter button can live in that
    /// screen's overlay stack, where it can be positioned against the turn
    /// banner and trip card instead of floating over the bare map.
    @Binding var cameraPosition: MapCameraPosition
    @Namespace private var mapScope

    var body: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            UserAnnotation()
            if let route = navigationEngine.route {
                MapPolyline(route.polyline)
                    .stroke(RoadTheme.asphalt, lineWidth: 10)
                MapPolyline(route.polyline)
                    .stroke(RoadTheme.accent, lineWidth: 6)
            }
        }
        .mapScope(mapScope)
    }
}
