import Foundation
import MapKit

enum NavState: Equatable {
    case idle
    case searchingDestination
    case calculatingRoute
    case navigating
    case rerouting
    case arrived
}

/// A lightweight, Equatable-by-id wrapper around the pieces of MKRoute.Step
/// the app actually needs. MKRoute.Step itself isn't Equatable/Identifiable,
/// which makes it awkward to hold in @Published state.
struct RouteStepInfo: Identifiable {
    let id = UUID()
    let instructions: String
    let distance: CLLocationDistance
    let polyline: MKPolyline
}

extension RouteStepInfo: Equatable {
    static func == (lhs: RouteStepInfo, rhs: RouteStepInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Events NavigationEngine emits as a trip progresses. Real turn-by-turn
/// speech and comedic banter both listen to the same stream, but they react
/// to it independently — see SpeechQueueManager for how the two are kept
/// from colliding.
enum NavigationEvent {
    case tripStarted(destinationName: String)
    case approachingManeuver(step: RouteStepInfo, distanceRemaining: CLLocationDistance)
    case advancedToStep(step: RouteStepInfo)
    case wentOffRoute
    case rerouted
    case arrived
    case idleTick
}

/// MapKit doesn't expose a structured maneuver type (turn left/right/etc.) —
/// only a human-readable instruction string. This is a best-effort heuristic
/// for picking a banner icon from that string; it errs toward a plain arrow
/// rather than guessing wrong.
enum ManeuverIcon {
    static func symbolName(for instructions: String) -> String {
        let text = instructions.lowercased()
        if text.contains("arrive") { return "flag.checkered.circle.fill" }
        if text.contains("u-turn") || text.contains("u turn") { return "arrow.uturn.left" }
        if text.contains("roundabout") { return "arrow.triangle.2.circlepath" }
        if text.contains("merge") { return "arrow.triangle.merge" }
        if text.contains("exit") || text.contains("ramp") { return "arrow.up.right.circle" }
        if text.contains("sharp left") { return "arrow.turn.up.left" }
        if text.contains("sharp right") { return "arrow.turn.up.right" }
        if text.contains("slight left") { return "arrow.up.left" }
        if text.contains("slight right") { return "arrow.up.right" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
