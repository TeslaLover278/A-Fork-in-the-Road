import SwiftUI
import MapKit

/// Full-screen search presented from the home screen's search bar.
///
/// Results are biased toward whatever part of the map the user is currently
/// looking at, so panning the map to another city and then searching
/// "parking" finds parking *there* rather than next to the driver.
struct DestinationSearchSheet: View {
    /// The home map's visible region, used to bias completions.
    let region: MKCoordinateRegion?
    let onSelect: (MKMapItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LocationSearchModel()
    @FocusState private var fieldFocused: Bool
    @State private var resolutionFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                searchField
                RoadRule()
                if model.isResolving {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(RoadTheme.teal)
                        Text("Finding this stop…")
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
                if resolutionFailed {
                    Text("Couldn't locate that stop. Try again or choose another result.")
                        .font(.subheadline)
                        .foregroundStyle(RoadTheme.ink)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .roadPanel()
                }
                results
            }
            .frame(maxWidth: 640)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(RoadTheme.paper.ignoresSafeArea())
        .foregroundStyle(RoadTheme.ink)
        .tint(RoadTheme.accent)
        .onAppear {
            model.region = region
            fieldFocused = true
        }
        .onChange(of: model.query) { _, _ in
            resolutionFailed = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                RoadMark()
                    .frame(width: 48, height: 56)
                Spacer(minLength: 16)
                Button("Cancel") { dismiss() }
                    .buttonStyle(RoadButtonStyle(secondary: true))
            }
            Text("DESTINATION / FIELD GUIDE")
                .font(RoadTheme.eyebrow)
                .foregroundStyle(RoadTheme.teal)
            Text("Where to?")
                .font(RoadTheme.title)
                .accessibilityAddTraits(.isHeader)
            Text("Find the place. Take your own way there.")
                .font(.body)
                .foregroundStyle(RoadTheme.muted)
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIND YOUR NEXT STOP")
                .font(RoadTheme.eyebrow)
                .foregroundStyle(RoadTheme.muted)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RoadTheme.teal)
                    .accessibilityHidden(true)

                TextField("Place or address", text: $model.query)
                    .font(.body)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Place or address")
                    .onSubmit {
                        if let first = model.results.first { pick(first) }
                    }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(RoadTheme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .roadPanel()
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(fieldFocused ? RoadTheme.teal : RoadTheme.line, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.query.isEmpty {
            emptyState
        } else if model.results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("No matches yet")
                    .font(.system(.title2, design: .serif, weight: .bold))
                Text("Try a place name, street address, or nearby landmark.")
                    .font(.body)
                    .foregroundStyle(RoadTheme.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .roadPanel()
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("PLACES TO GO")
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(RoadTheme.teal)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.results, id: \.self) { result in
                    Button { pick(result) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title)
                                    .font(.system(.headline, design: .serif, weight: .bold))
                                    .foregroundStyle(RoadTheme.ink)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(RoadTheme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(RoadTheme.teal)
                                .accessibilityHidden(true)
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .roadPanel()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isResolving)
                    .accessibilityHint("Choose this destination")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A place worth finding.")
                .font(.system(.title2, design: .serif, weight: .bold))
            Text("Search for a place or address")
                .font(.headline)
            RoadRule()
            Text("Or close this and tap anywhere on the map to drop a pin.")
                .font(.body)
                .foregroundStyle(RoadTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .roadPanel()
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        guard !model.isResolving else { return }
        resolutionFailed = false
        fieldFocused = false
        model.resolve(completion) { item in
            guard let item else {
                resolutionFailed = true
                return
            }
            onSelect(item)
            dismiss()
        }
    }
}

/// Wraps MKLocalSearchCompleter. A completion is only a *suggestion* — it
/// carries no coordinate — so picking one still costs a second MKLocalSearch
/// round trip to turn it into a routable MKMapItem, which is what
/// `resolve` does.
@MainActor
final class LocationSearchModel: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isResolving = false

    var region: MKCoordinateRegion? {
        didSet {
            if let region { completer.region = region }
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func resolve(_ completion: MKLocalSearchCompletion, handler: @escaping (MKMapItem?) -> Void) {
        isResolving = true
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { response, _ in
            Task { @MainActor in
                self.isResolving = false
                handler(response?.mapItems.first)
            }
        }
    }
}

extension LocationSearchModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let updated = completer.results
        Task { @MainActor in
            self.results = updated
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
        #if DEBUG
        print("Search completer error: \(error.localizedDescription)")
        #endif
    }
}
