import SwiftUI
import MapKit

/// The screen you land on: a live map of where you are, a search bar, and a
/// way into the menu. Nothing here talks to NavigationEngine directly — it
/// hands a chosen MKMapItem back up to ContentView via `onStart`, which is
/// the only thing allowed to begin a trip.
struct HomeView: View {
    @ObservedObject var locationService: LocationService
    @ObservedObject var unitSettings: UnitSettings
    /// True while NavigationEngine is fetching the route for a started trip.
    let isCalculatingRoute: Bool
    let onOpenMenu: () -> Void
    let onStart: (MKMapItem) -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showSearch = false
    @State private var destination: SelectedDestination?
    @State private var preview: RoutePreview?
    @State private var previewTask: Task<Void, Never>?
    @State private var namingTask: Task<Void, Never>?
    @Namespace private var mapScope
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var hasLocationFix: Bool { locationService.currentLocation != nil }

    var body: some View {
        GeometryReader { geometry in
            map
                .safeAreaInset(edge: .top, spacing: 2) {
                    ViewThatFits(in: .vertical) {
                        header
                        ScrollView { header }
                    }
                    .frame(maxWidth: 620, maxHeight: geometry.size.height * 0.4)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .safeAreaInset(edge: .bottom, spacing: 2) {
                    ViewThatFits(in: .vertical) {
                        bottomControls
                        ScrollView { bottomControls }
                    }
                    .frame(maxWidth: 620, maxHeight: geometry.size.height * 0.42)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
                .overlay {
                    if isCalculatingRoute {
                        calculatingOverlay
                    }
                }
        }
        .foregroundStyle(RoadTheme.ink)
        .sheet(isPresented: $showSearch) {
            DestinationSearchSheet(region: visibleRegion) { item in
                select(SelectedDestination(mapItem: item), recenter: true)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            topControls
            locationButton
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if let destination {
            destinationCard(for: destination)
        } else {
            mapHint
        }
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, scope: mapScope) {
                UserAnnotation()
                if let destination {
                    Marker(destination.name, systemImage: "mappin", coordinate: destination.coordinate)
                        .tint(RoadTheme.accent)
                }
            }
            .mapControls {
                MapCompass()
            }
            .mapScope(mapScope)
            // Pan and zoom are drag and pinch gestures, so a discrete tap
            // doesn't fight them — this only fires on a real tap.
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                dropPin(at: coordinate)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
            }
            .ignoresSafeArea()
        }
    }

    /// Sits directly under the search bar rather than in MapKit's default
    /// top-trailing spot, so it doesn't compete with the compass there. Only
    /// present once the map has been panned away from the user — until then
    /// the camera is already centred and the button would be a no-op.
    private var locationButton: some View {
        HStack {
            Spacer()
            if cameraPosition.hasBeenMovedByUser {
                RecenterButton(action: recenter)
                    .padding(.trailing)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameraPosition.hasBeenMovedByUser)
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .userLocation(fallback: .automatic)
        }
    }

    // MARK: - Overlays

    private var topControls: some View {
        let layout = verticalSizeClass == .compact
            ? AnyLayout(HStackLayout(spacing: 14))
            : AnyLayout(VStackLayout(spacing: 14))
        return layout {
            HStack(spacing: 12) {
                RoadMark()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A FORK IN THE ROAD")
                        .font(RoadTheme.eyebrow)
                    Text("One route. Two opinions.")
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(RoadTheme.muted)
                }
                Spacer(minLength: 0)
                Button(action: onOpenMenu) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(RoadButtonStyle(secondary: true))
                .accessibilityLabel("Menu")
            }

            Button {
                showSearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    Text(destination?.name ?? "Where are we headed?")
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(RoadButtonStyle())
            .accessibilityLabel("Search for a destination")
        }
        .padding(16)
        .roadPanel()
        .padding(.horizontal)
        .padding(.top, 2)
    }

    private var mapHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            if verticalSizeClass != .compact {
                Text("THE OPEN ROAD IS CALLING")
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(RoadTheme.teal)
                Text("Pick a place.\nBring the backseat drivers.")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                RoadRule()
            }
            Label(
                hasLocationFix ? "Tap the map to drop a pin, or search above." : "Waiting for a GPS fix…",
                systemImage: hasLocationFix ? "mappin.and.ellipse" : "location"
            )
            .font(.footnote)
            .foregroundStyle(RoadTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .roadPanel()
        .padding(.horizontal)
        .padding(.bottom, 2)
    }

    private func destinationCard(for destination: SelectedDestination) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR NEXT STOP")
                .font(RoadTheme.eyebrow)
                .foregroundStyle(RoadTheme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = destination.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(RoadTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let preview, preview.destinationID == destination.id {
                Label(
                    "\(DurationFormatter.short(preview.travelTime)) · \(unitSettings.shortDistance(preview.distance))",
                    systemImage: "car.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RoadTheme.muted)
            } else if hasLocationFix {
                Label("Estimating drive…", systemImage: "car.fill")
                    .font(.subheadline)
                    .foregroundStyle(RoadTheme.muted)
            }

            RoadRule()
            HStack(spacing: 12) {
                Button {
                    onStart(destination.mapItem)
                } label: {
                    Label("Hit the road", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RoadButtonStyle())
                .disabled(!hasLocationFix)

                Button {
                    clearDestination()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RoadButtonStyle(secondary: true))
                .accessibilityLabel("Clear destination")
            }

            if !hasLocationFix {
                Text("Waiting for a GPS fix before a trip can start.")
                    .font(.caption)
                    .foregroundStyle(RoadTheme.muted)
            }
        }
        .padding(18)
        .roadPanel()
        .padding(.horizontal)
        .padding(.bottom, 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var calculatingOverlay: some View {
        VStack(spacing: 16) {
            RoadMark()
                .frame(width: 56, height: 56)
            Text("Plotting the adventure.")
                .font(.system(.title2, design: .serif, weight: .bold))
            ProgressView("Finding a route…")
                .tint(RoadTheme.accent)
        }
        .padding(28)
        .roadPanel()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoadTheme.asphalt.opacity(0.55))
        .accessibilityAddTraits(.isModal)
        .ignoresSafeArea()
    }

    // MARK: - Destination selection

    private func select(_ new: SelectedDestination, recenter: Bool) {
        namingTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            destination = new
            preview = nil
        }
        if recenter {
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: new.coordinate,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                ))
            }
        }
        loadPreview(for: new)
    }

    private func clearDestination() {
        namingTask?.cancel()
        previewTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            destination = nil
            preview = nil
        }
    }

    /// A tap on the map gives a coordinate and nothing else, so the pin
    /// appears immediately under the finger and its real name arrives from
    /// the geocoder a moment later. The camera deliberately does not move —
    /// the user just chose where to look.
    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = SelectedDestination.droppedPinName
        let pin = SelectedDestination(mapItem: item)
        select(pin, recenter: false)

        namingTask = Task { @MainActor in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
                  !Task.isCancelled else { return }
            let named = MKMapItem(placemark: MKPlacemark(placemark: placemark))
            named.name = placemark.name ?? SelectedDestination.droppedPinName
            // Only apply if this is still the pin on screen — the user may
            // have tapped somewhere else while the geocoder was working.
            guard destination?.id == pin.id else { return }
            destination = SelectedDestination(id: pin.id, mapItem: named)
        }
    }

    /// Drive time and distance for the card. `calculateETA` is cheaper than a
    /// full route request, and this is only a preview — the real route is
    /// calculated by NavigationEngine once the trip actually starts.
    private func loadPreview(for destination: SelectedDestination) {
        previewTask?.cancel()
        guard let origin = locationService.currentLocation else { return }
        previewTask = Task { @MainActor in
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
            request.destination = destination.mapItem
            request.transportType = .automobile
            guard let response = try? await MKDirections(request: request).calculateETA(),
                  !Task.isCancelled else { return }
            preview = RoutePreview(
                destinationID: destination.id,
                distance: response.distance,
                travelTime: response.expectedTravelTime
            )
        }
    }
}

/// A place the user has picked but not yet departed for.
struct SelectedDestination: Identifiable, Equatable {
    static let droppedPinName = "Dropped pin"

    let id: UUID
    let mapItem: MKMapItem

    init(id: UUID = UUID(), mapItem: MKMapItem) {
        self.id = id
        self.mapItem = mapItem
    }

    var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }

    var name: String { mapItem.name ?? Self.droppedPinName }

    /// The formatted address, unless it just repeats the name.
    var subtitle: String? {
        guard let title = mapItem.placemark.title, title != name else { return nil }
        return title
    }

    static func == (lhs: SelectedDestination, rhs: SelectedDestination) -> Bool {
        lhs.id == rhs.id
    }
}

private struct RoutePreview {
    let destinationID: UUID
    let distance: CLLocationDistance
    let travelTime: TimeInterval
}
