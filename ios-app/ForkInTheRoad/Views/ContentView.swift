import SwiftUI
import MapKit
import Combine

/// App root: owns every service/engine and wires them together. This is
/// the one place that decides "this NavigationEvent means: speak this real
/// instruction, AND let BanterEngine react to it" — see `handle(_:)` below.
struct ContentView: View {
    @StateObject private var locationService = LocationService()
    @StateObject private var navigationEngine = NavigationEngine()
    @StateObject private var banterSettings: BanterSettings
    @StateObject private var speechQueue: SpeechQueueManager
    @StateObject private var banterEngine: BanterEngine

    @State private var showSettings = false

    init() {
        let settings = BanterSettings()
        let queue = SpeechQueueManager()
        _banterSettings = StateObject(wrappedValue: settings)
        _speechQueue = StateObject(wrappedValue: queue)
        _banterEngine = StateObject(wrappedValue: BanterEngine(settings: settings, speechQueue: queue))
    }

    var body: some View {
        Group {
            switch navigationEngine.state {
            case .idle, .searchingDestination, .calculatingRoute:
                SearchDestinationView(hasLocationFix: locationService.currentLocation != nil) { destination in
                    start(to: destination)
                }
            case .navigating, .rerouting:
                NavigationScreen(
                    navigationEngine: navigationEngine,
                    banterEngine: banterEngine,
                    onSettings: { showSettings = true },
                    onEnd: endTrip
                )
            case .arrived:
                TripSummaryView(destinationName: navigationEngine.destinationName, onDone: endTrip)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: banterSettings)
        }
        .onAppear {
            locationService.requestPermission()
        }
        .onReceive(navigationEngine.events) { event in
            handle(event)
        }
        .onReceive(locationService.$currentLocation.compactMap { $0 }) { location in
            navigationEngine.updateProgress(with: location)
        }
    }

    private func start(to destination: MKMapItem) {
        guard let origin = locationService.currentLocation else { return }
        banterEngine.resetForNewTrip()
        Task {
            await navigationEngine.startTrip(to: destination, from: origin)
        }
    }

    private func endTrip() {
        navigationEngine.cancelTrip()
        speechQueue.stopAllBanter()
    }

    /// Converts a NavigationEvent into a real spoken instruction (when one
    /// applies) and always forwards the event to BanterEngine. Real
    /// instructions are spoken via `speakNavigation`, which unconditionally
    /// preempts any banter in progress — that's the whole guarantee.
    private func handle(_ event: NavigationEvent) {
        switch event {
        case .tripStarted(let destinationName):
            speechQueue.speakNavigation("Starting navigation to \(destinationName).")
        case .approachingManeuver(let step, let distanceRemaining):
            speechQueue.speakNavigation("In \(Int(distanceRemaining)) meters, \(step.instructions).")
        case .wentOffRoute:
            speechQueue.speakNavigation("Rerouting.")
        case .arrived:
            speechQueue.speakNavigation("You have arrived at \(navigationEngine.destinationName).")
        case .rerouted, .advancedToStep, .idleTick:
            break
        }
        banterEngine.handle(event)
    }
}

/// The main driving screen: map + always-on-top turn banner + an optional
/// banter caption bubble that never displaces the banner above it.
private struct NavigationScreen: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @ObservedObject var banterEngine: BanterEngine
    let onSettings: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NavigationMapView(navigationEngine: navigationEngine)
                .ignoresSafeArea()

            VStack {
                TurnBannerView(navigationEngine: navigationEngine)
                Spacer()
                if let caption = banterEngine.currentCaption {
                    BanterCaptionView(personaID: caption.personaID, text: caption.text)
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 8)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    Button(action: onEnd) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}
