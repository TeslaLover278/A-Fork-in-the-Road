import SwiftUI
import MapKit

struct SearchDestinationView: View {
    let hasLocationFix: Bool
    let onSelect: (MKMapItem) -> Void

    @State private var queryFragment = ""
    @StateObject private var completerDelegate = SearchCompleterDelegate()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasLocationFix {
                    Label("Waiting for a GPS fix…", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                TextField("Where to?", text: $queryFragment)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: queryFragment) { _, newValue in
                        completerDelegate.update(query: newValue)
                    }

                List(Array(completerDelegate.results.enumerated()), id: \.offset) { _, result in
                    Button {
                        completerDelegate.resolve(result) { item in
                            if let item {
                                onSelect(item)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.title)
                                .font(.body)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Fork in the Road")
        }
    }
}

@MainActor
private final class SearchCompleterDelegate: NSObject, ObservableObject {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion, handler: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            handler(response?.mapItems.first)
        }
    }
}

extension SearchCompleterDelegate: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        #if DEBUG
        print("Search completer error: \(error.localizedDescription)")
        #endif
    }
}
