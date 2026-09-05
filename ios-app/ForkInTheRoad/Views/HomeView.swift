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

    private var hasLocationFix: Bool { locationService.currentLocation != nil }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topControls
            if let destination {
                destinationCard(for: destination)
            } else {
                mapHint
            }
            if isCalculatingRoute {
                calculatingOverlay
            }
        }
        .sheet(isPresented: $showSearch) {
            DestinationSearchSheet(region: visibleRegion) { item in
                select(SelectedDestination(mapItem: item), recenter: true)
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                UserAnnotation()
                if let destination {
                    Marker(destination.name, systemImage: "mappin", coordinate: destination.coordinate)
                        .tint(.red)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
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

    // MARK: - Overlays

    private var topControls: some View {
        HStack(spacing: 10) {
            Button(action: onOpenMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Menu")

            Button {
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(destination?.name ?? "Where to?")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(destination == nil ? Color.secondary : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.regularMaterial, in: Capsule())
            }
            .accessibilityLabel("Search for a destination")
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var mapHint: some View {
        VStack {
            Spacer()
            Text(hasLocationFix ? "Tap anywhere on the map to drop a pin" : "Waiting for a GPS fix…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
        }
    }

    private func destinationCard(for destination: SelectedDestination) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let preview, preview.destinationID == destination.id {
                    Label(
                        "\(DurationFormatter.short(preview.travelTime)) · \(unitSettings.shortDistance(preview.distance))",
                        systemImage: "car.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                } else if hasLocationFix {
                    Label("Estimating drive…", systemImage: "car.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Button {
                        onStart(destination.mapItem)
                    } label: {
                        Label("Go", systemImage: "location.north.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasLocationFix)

                    Button {
                        clearDestination()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear destination")
                }

                if !hasLocationFix {
                    Text("Waiting for a GPS fix before a trip can start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var calculatingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding a route…")
                .font(.subheadline)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.15))
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
