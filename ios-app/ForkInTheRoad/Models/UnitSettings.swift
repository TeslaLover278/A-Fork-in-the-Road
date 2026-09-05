import Foundation
import CoreLocation

/// Metric vs. imperial, for everything the app shows or says.
enum UnitSystem: Equatable {
    case metric
    case imperial
}

/// What the user picked in the menu. `.automatic` defers to the device
/// region, which is what most people want and means a fresh install is
/// already correct without anyone visiting the menu.
enum UnitPreference: String, CaseIterable, Identifiable, Codable {
    case automatic
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

/// Distance unit preference, persisted across launches.
///
/// Backed by UserDefaults directly rather than @AppStorage for the same
/// reason as `BanterSettings`: it is read by non-view code (the spoken
/// instruction text in ContentView), not only by SwiftUI views.
@MainActor
final class UnitSettings: ObservableObject {
    @Published var preference: UnitPreference {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Keys.preference) }
    }

    private enum Keys {
        static let preference = "units.preference"
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Keys.preference) ?? ""
        preference = UnitPreference(rawValue: stored) ?? .automatic
    }

    /// The system actually in effect right now.
    var system: UnitSystem {
        switch preference {
        case .automatic: return Self.deviceSystem
        case .metric: return .metric
        case .imperial: return .imperial
        }
    }

    /// What the device region implies. Note the UK is `.uk`, not `.metric`,
    /// and signs road distances in miles — so anything that isn't `.metric`
    /// lands on imperial here, which is the right call for road distances.
    nonisolated static var deviceSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    private var formatter: DistanceFormatter { DistanceFormatter(system: system) }

    /// Compact, for the turn banner and cards: "450 ft", "0.6 mi", "1.2 km".
    func shortDistance(_ meters: CLLocationDistance) -> String {
        formatter.short(meters)
    }

    /// Read aloud, so it gets words and friendlier rounding: "300 feet".
    func spokenDistance(_ meters: CLLocationDistance) -> String {
        formatter.spoken(meters)
    }
}

/// Pure formatting, kept free of any settings object so it can be reasoned
/// about (and tested) on its own.
struct DistanceFormatter {
    let system: UnitSystem

    private static let feetPerMeter = 3.280839895
    private static let metersPerMile = 1609.344

    /// Where each system stops using its small unit. Both sit just under a
    /// round number so rounding can never print "1000 m" or "1000 ft"
    /// immediately before the switch to km/mi.
    private static let metersCutoff = 950.0
    private static let feetCutoff = 950.0

    func short(_ meters: CLLocationDistance) -> String {
        let meters = max(0, meters)
        switch system {
        case .metric:
            if meters < Self.metersCutoff {
                return "\(Int(Self.round(meters, to: 10))) m"
            }
            return "\(Self.decimal(meters / 1000)) km"
        case .imperial:
            let feet = meters * Self.feetPerMeter
            if feet < Self.feetCutoff {
                return "\(Int(Self.round(feet, to: 10))) ft"
            }
            return "\(Self.decimal(meters / Self.metersPerMile)) mi"
        }
    }

    func spoken(_ meters: CLLocationDistance) -> String {
        let meters = max(0, meters)
        switch system {
        case .metric:
            if meters < Self.metersCutoff {
                let rounded = Int(Self.round(meters, to: meters < 100 ? 10 : 50))
                return "\(rounded) meter\(rounded == 1 ? "" : "s")"
            }
            return unitPhrase(meters / 1000, singular: "kilometer", plural: "kilometers")
        case .imperial:
            let feet = meters * Self.feetPerMeter
            if feet < Self.feetCutoff {
                let rounded = Int(Self.round(feet, to: feet < 100 ? 10 : 50))
                return "\(rounded) \(rounded == 1 ? "foot" : "feet")"
            }
            return unitPhrase(meters / Self.metersPerMile, singular: "mile", plural: "miles")
        }
    }

    private func unitPhrase(_ value: Double, singular: String, plural: String) -> String {
        let text = Self.decimal(value)
        return "\(text) \(text == "1" ? singular : plural)"
    }

    /// One decimal place under 10, none above — "0.6", "4.2", "23". Trailing
    /// ".0" is dropped so nothing ever says "one point zero miles".
    private static func decimal(_ value: Double) -> String {
        if value >= 10 {
            return String(Int(value.rounded()))
        }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private static func round(_ value: Double, to increment: Double) -> Double {
        max(increment, (value / increment).rounded() * increment)
    }
}

/// Trip durations, shown next to a distance on the destination card.
enum DurationFormatter {
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}
