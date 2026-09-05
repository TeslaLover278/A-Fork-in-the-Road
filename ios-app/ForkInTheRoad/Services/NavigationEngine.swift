import Foundation
import MapKit
import Combine

/// Owns real routing and progress-tracking. This is the only thing that may
/// decide what real turn-by-turn instructions get spoken or when a reroute
/// happens — the comedic layer (BanterEngine) only ever listens to `events`,
/// it never influences routing.
@MainActor
final class NavigationEngine: ObservableObject {
    @Published private(set) var state: NavState = .idle
    @Published private(set) var route: MKRoute?
    @Published private(set) var steps: [RouteStepInfo] = []
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var distanceToNextManeuver: CLLocationDistance = 0
    @Published private(set) var distanceRemainingTotal: CLLocationDistance = 0
    @Published private(set) var etaMinutes: Int = 0
    @Published private(set) var destinationName: String = ""

    let events = PassthroughSubject<NavigationEvent, Never>()

    private var destinationItem: MKMapItem?
    private var offRouteStrikeCount = 0
    private var announcedApproachForStepIndex: Int?
    private var lastManeuverEventTime = Date()
    private var idleTimer: Timer?

    private let offRouteThresholdMeters: CLLocationDistance = 40
    private let offRouteStrikesRequired = 3
    private let approachAnnounceDistance: CLLocationDistance = 400
    private let stepAdvanceRadius: CLLocationDistance = 15
    private let arrivalRadius: CLLocationDistance = 25
    private let idleCheckInterval: TimeInterval = 45

    func startTrip(to destination: MKMapItem, from origin: CLLocation) async {
        destinationItem = destination
        destinationName = destination.name ?? "your destination"
        state = .calculatingRoute
        let originItem = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        await calculateRoute(from: originItem, to: destination)
    }

    func cancelTrip() {
        state = .idle
        route = nil
        steps = []
        currentStepIndex = 0
        destinationItem = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// Feed every new location fix here while `state` is `.navigating`.
    func updateProgress(with location: CLLocation) {
        guard state == .navigating, !steps.isEmpty else { return }

        advanceStepsIfNeeded(location: location)

        if currentStepIndex >= steps.count - 1, let destCoordinate = destinationItem?.placemark.coordinate {
            let destLocation = CLLocation(latitude: destCoordinate.latitude, longitude: destCoordinate.longitude)
            let distanceToDest = location.distance(from: destLocation)
            distanceToNextManeuver = distanceToDest
            if distanceToDest < arrivalRadius {
                finishTrip()
                return
            }
        }

        announceApproachIfNeeded()
        checkOffRoute(location: location)
    }

    // MARK: - Route calculation

    private func calculateRoute(from origin: MKMapItem, to destination: MKMapItem) async {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let best = response.routes.first else {
                state = .idle
                return
            }
            let wasRerouting = state == .rerouting
            applyNewRoute(best)
            state = .navigating
            // Step 0 is typically a zero-distance "Depart" instruction for
            // the starting point — skip straight to the first real maneuver.
            currentStepIndex = steps.count > 1 ? 1 : 0
            startIdleTimer()
            if wasRerouting {
                events.send(.rerouted)
            } else {
                events.send(.tripStarted(destinationName: destinationName))
            }
        } catch {
            #if DEBUG
            print("Route calculation failed: \(error.localizedDescription)")
            #endif
            state = .idle
        }
    }

    private func applyNewRoute(_ newRoute: MKRoute) {
        route = newRoute
        steps = newRoute.steps.map {
            RouteStepInfo(instructions: $0.instructions, distance: $0.distance, polyline: $0.polyline)
        }
        distanceRemainingTotal = newRoute.distance
        etaMinutes = Int((newRoute.expectedTravelTime / 60).rounded())
        offRouteStrikeCount = 0
        announcedApproachForStepIndex = nil
        lastManeuverEventTime = Date()
    }

    private func reroute(from location: CLLocation) async {
        guard let destinationItem else { return }
        state = .rerouting
        events.send(.wentOffRoute)
        let originItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        await calculateRoute(from: originItem, to: destinationItem)
    }

    private func finishTrip() {
        state = .arrived
        idleTimer?.invalidate()
        idleTimer = nil
        events.send(.arrived)
    }

    // MARK: - Progress helpers

    /// NOTE: this treats "distance from the current location to the end of
    /// the current step's polyline" as distance-to-next-maneuver. MapKit
    /// doesn't document step boundary semantics precisely enough to
    /// guarantee this lines up exactly with where `instructions` should be
    /// spoken — it's a reasonable approximation that should be sanity
    /// checked on a real device/route before shipping.
    private func advanceStepsIfNeeded(location: CLLocation) {
        while currentStepIndex < steps.count - 1 {
            let step = steps[currentStepIndex]
            let distanceToStepEnd = distanceFromEnd(of: step.polyline, to: location.coordinate)
            if distanceToStepEnd < stepAdvanceRadius {
                currentStepIndex += 1
                announcedApproachForStepIndex = nil
                lastManeuverEventTime = Date()
                events.send(.advancedToStep(step: steps[currentStepIndex]))
            } else {
                distanceToNextManeuver = distanceToStepEnd
                break
            }
        }
    }

    private func announceApproachIfNeeded() {
        guard currentStepIndex < steps.count else { return }
        if distanceToNextManeuver <= approachAnnounceDistance, announcedApproachForStepIndex != currentStepIndex {
            announcedApproachForStepIndex = currentStepIndex
            events.send(.approachingManeuver(step: steps[currentStepIndex], distanceRemaining: distanceToNextManeuver))
        }
    }

    private func checkOffRoute(location: CLLocation) {
        guard currentStepIndex < steps.count else { return }
        let perpDistance = perpendicularDistance(from: location.coordinate, to: steps[currentStepIndex].polyline)
        if perpDistance > offRouteThresholdMeters {
            offRouteStrikeCount += 1
            if offRouteStrikeCount >= offRouteStrikesRequired {
                offRouteStrikeCount = 0
                Task { await reroute(from: location) }
            }
        } else {
            offRouteStrikeCount = 0
        }
    }

    // MARK: - Idle chatter timer

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .navigating else { return }
                if Date().timeIntervalSince(self.lastManeuverEventTime) > self.idleCheckInterval {
                    self.events.send(.idleTick)
                    self.lastManeuverEventTime = Date()
                }
            }
        }
    }

    // MARK: - Geometry helpers

    private func perpendicularDistance(from coordinate: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        let point = MKMapPoint(coordinate)
        let points = polylinePoints(polyline)
        guard points.count > 1 else { return 0 }
        var minDistance = Double.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            minDistance = min(minDistance, point.distance(toSegmentFrom: points[i], to: points[i + 1]))
        }
        return minDistance
    }

    private func distanceFromEnd(of polyline: MKPolyline, to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let last = polylinePoints(polyline).last else { return 0 }
        let end = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        return end.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func polylinePoints(_ polyline: MKPolyline) -> [MKMapPoint] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords.map { MKMapPoint($0) }
    }
}

private extension MKMapPoint {
    /// Shortest distance from this point to the segment [a, b], in meters.
    func distance(toSegmentFrom a: MKMapPoint, to b: MKMapPoint) -> CLLocationDistance {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let closest: MKMapPoint
        if lengthSquared == 0 {
            closest = a
        } else {
            var t = ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared
            t = max(0, min(1, t))
            closest = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
        }
        return distance(to: closest)
    }
}
