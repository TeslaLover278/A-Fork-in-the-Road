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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                results
            }
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            model.region = region
            fieldFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Place or address", text: $model.query)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    if let first = model.results.first { pick(first) }
                }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .padding()
    }

    @ViewBuilder
    private var results: some View {
        if model.query.isEmpty {
            emptyState
        } else if model.results.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            List(model.results, id: \.self) { result in
                Button { pick(result) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .top) {
                if model.isResolving {
                    ProgressView()
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Search for a place or address")
                .font(.headline)
            Text("Or close this and tap anywhere on the map to drop a pin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        fieldFocused = false
        model.resolve(completion) { item in
            guard let item else { return }
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
