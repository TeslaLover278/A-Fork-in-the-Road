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
    @StateObject private var unitSettings: UnitSettings

    @State private var showMenu = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = BanterSettings()
        let queue = SpeechQueueManager()
        let units = UnitSettings()
        _banterSettings = StateObject(wrappedValue: settings)
        _speechQueue = StateObject(wrappedValue: queue)
        _unitSettings = StateObject(wrappedValue: units)
        _banterEngine = StateObject(wrappedValue: BanterEngine(settings: settings, speechQueue: queue, unitSettings: units))
    }

    var body: some View {
        Group {
            switch navigationEngine.state {
            case .idle, .searchingDestination, .calculatingRoute:
                HomeView(
                    locationService: locationService,
                    unitSettings: unitSettings,
                    isCalculatingRoute: navigationEngine.state == .calculatingRoute,
                    onOpenMenu: { showMenu = true },
                    onStart: start
                )
            case .navigating, .rerouting:
                NavigationScreen(
                    navigationEngine: navigationEngine,
                    banterEngine: banterEngine,
                    banterSettings: banterSettings,
                    unitSettings: unitSettings,
                    onMenu: { showMenu = true },
                    onEnd: endTrip
                )
            case .arrived:
                TripSummaryView(destinationName: navigationEngine.destinationName, onDone: endTrip)
            }
        }
        .sheet(isPresented: $showMenu) {
            MenuView(
                banterSettings: banterSettings,
                unitSettings: unitSettings,
                speechQueue: speechQueue
            )
        }
        .onAppear {
            locationService.requestPermission()
        }
        .onChange(of: scenePhase) { _, phase in
            // The set of installed voices can change while we're backgrounded
            // — downloading an Enhanced voice is exactly what Settings tells
            // the user to go and do — so re-resolve on the way back in.
            if phase == .active { VoiceCatalog.shared.invalidate() }
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
    ///
    /// Turns are the exception: by default the plain instruction below is
    /// skipped entirely and Dez/Vale deliver the turn themselves (see
    /// `BanterEngine.announceManeuver`), unless the user turned on real
    /// directions in Settings — `mustUseRealDirections` covers that toggle
    /// plus the cases where there's simply nobody left to say it.
    private func handle(_ event: NavigationEvent) {
        switch event {
        case .tripStarted(let destinationName):
            speechQueue.speakNavigation("Starting navigation to \(destinationName).")
        case .approachingManeuver(let step, let distanceRemaining):
            if banterSettings.mustUseRealDirections {
                speechQueue.speakNavigation("In \(unitSettings.spokenDistance(distanceRemaining)), \(step.instructions).")
            }
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
    @ObservedObject var banterSettings: BanterSettings
    @ObservedObject var unitSettings: UnitSettings
    let onMenu: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NavigationMapView(navigationEngine: navigationEngine)
                .ignoresSafeArea()

            VStack {
                TurnBannerView(navigationEngine: navigationEngine, unitSettings: unitSettings)
                Spacer()
                if banterSettings.showCaptions, let caption = banterEngine.currentCaption {
                    BanterCaptionView(personaID: caption.personaID, text: caption.text)
                        .padding(.bottom, 8)
                }
                TripProgressView(navigationEngine: navigationEngine, unitSettings: unitSettings)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onMenu) {
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
