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
        _banterEngine = StateObject(wrappedValue: BanterEngine(settings: settings, speechQueue: queue))
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
                    speechQueue: speechQueue,
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
            // The installed system voices can change while we're backgrounded,
            // so re-resolve the plain navigation voice on the way back in.
            if phase == .active { speechQueue.invalidateNavigationVoice() }
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
    /// Turns are the exception: the plain instruction below is skipped when a
    /// recorded character clip is going to call the turn out instead (see
    /// `BanterEngine.announceManeuver`). Both conditions have to hold for that
    /// — `mustUseRealDirections` covers the Settings toggle and the cases where
    /// nobody is left to speak at all, and `canAnnounceManeuver` covers whether
    /// a recording exists for *this* maneuver. Anything a recording can't
    /// describe (sharp turns, roundabouts, merges, exits, u-turns) therefore
    /// still gets announced properly rather than passing in silence.
    private func handle(_ event: NavigationEvent) {
        switch event {
        case .tripStarted(let destinationName):
            speechQueue.speakNavigation("Starting navigation to \(destinationName).")
        case .approachingManeuver(let step, let distanceRemaining):
            if banterSettings.mustUseRealDirections || !banterEngine.canAnnounceManeuver(step: step) {
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
/// banter waveform panel that never displaces the banner above it.
private struct NavigationScreen: View {
    @ObservedObject var navigationEngine: NavigationEngine
    @ObservedObject var speechQueue: SpeechQueueManager
    @ObservedObject var banterSettings: BanterSettings
    @ObservedObject var unitSettings: UnitSettings
    let onMenu: () -> Void
    let onEnd: () -> Void

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let layout = isWide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(spacing: 12))

            ZStack {
                NavigationMapView(navigationEngine: navigationEngine, cameraPosition: $cameraPosition)
                    .ignoresSafeArea()

                layout {
                    ViewThatFits(in: .vertical) {
                        TurnBannerView(navigationEngine: navigationEngine, unitSettings: unitSettings)
                        ScrollView {
                            TurnBannerView(navigationEngine: navigationEngine, unitSettings: unitSettings)
                        }
                    }
                    .frame(maxWidth: isWide ? 340 : 620)
                    .frame(maxHeight: geometry.size.height * (isWide ? 1 : 0.32))

                    Spacer(minLength: 16)

                    VStack(spacing: 10) {
                        // In the layout flow rather than pinned to the map's edge, so
                        // it always lands just above the waveform/trip card no matter
                        // how tall those grow — and stays out of the vertical middle,
                        // where it sat over the road ahead.
                        if cameraPosition.hasBeenMovedByUser {
                            HStack {
                                Spacer()
                                RecenterButton(action: recenter)
                            }
                        }
                        ViewThatFits(in: .vertical) {
                            tripCards
                            ScrollView { tripCards }
                                .defaultScrollAnchor(.bottom)
                        }
                        HStack(spacing: 10) {
                            Button(action: onMenu) {
                                Label("Crew", systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RoadButtonStyle(secondary: true))
                            .accessibilityLabel("Open menu and voice settings")
                            Button(action: onEnd) {
                                Label("End trip", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RoadButtonStyle())
                        }
                    }
                    .frame(maxWidth: isWide ? 340 : 620)
                    .frame(maxHeight: geometry.size.height * (isWide ? 1 : 0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    /// The waveform is driven straight off the speech queue rather than off
    /// BanterEngine: the queue is what actually knows a clip is playing and
    /// whose it is, and the level it exposes is the real playback meter.
    private var tripCards: some View {
        VStack(spacing: 10) {
            if banterSettings.showWaveform,
               speechQueue.isSpeakingBanter,
               let personaID = speechQueue.activePersonaID {
                BanterWaveformView(personaID: personaID) {
                    speechQueue.currentBanterLevel()
                }
            }
            TripProgressView(navigationEngine: navigationEngine, unitSettings: unitSettings)
        }
    }

    /// Hands the camera back to MapKit's user-location tracking. Mid-drive
    /// this matters more than on the home map — dragging the map back by hand
    /// is exactly the fiddling we don't want happening at the wheel.
    private func recenter() {
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .userLocation(fallback: .automatic)
        }
    }
}
