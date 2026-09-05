import SwiftUI
import MapKit
import CoreLocation

/// A place chosen for a frame, ready to write onto a `FrameMarker`.
nonisolated struct ResolvedPlace: Sendable {
    let name: String
    let coordinate: CLLocationCoordinate2D?
}

enum CurrentLocationError: Error {
    case denied
    case unavailable
}

/// One-shot "where am I" lookup. Starting live updates also drives the permission
/// prompt, so there is no separate authorization dance to manage.
enum CurrentLocation {
    /// Gives up after `timeout` so an automatic lookup can't wait on a fix forever.
    static func resolve(timeout: Duration = .seconds(15)) async throws -> ResolvedPlace {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        for try await update in CLLocationUpdate.liveUpdates(.default) {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                throw CurrentLocationError.denied
            }
            if let location = update.location {
                return ResolvedPlace(
                    name: await placeName(for: location),
                    coordinate: location.coordinate
                )
            }
            if ContinuousClock.now >= deadline {
                throw CurrentLocationError.unavailable
            }
        }
        throw CurrentLocationError.unavailable
    }

    /// Prefers the kind of name a photographer would write down — a landmark or a short
    /// address rather than a full postal one — and falls back to raw coordinates.
    private static func placeName(for location: CLLocation) async -> String {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = (try? await request.mapItems)?.first
        else {
            return coordinateLabel(location.coordinate)
        }

        if let name = item.name, !name.isEmpty {
            return name
        }
        if let shortAddress = item.address?.shortAddress, !shortAddress.isEmpty {
            return shortAddress
        }
        return coordinateLabel(location.coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}

/// Wraps `MKLocalSearchCompleter` so the sheet can read completions as observable state.
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    /// Completions carry no coordinate, so run the full search to recover one.
    /// A failure here still yields a usable name.
    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedPlace {
        let name = Self.displayName(for: completion)
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first
        else {
            return ResolvedPlace(name: name, coordinate: nil)
        }
        return ResolvedPlace(name: name, coordinate: item.location.coordinate)
    }

    static func displayName(for completion: MKLocalSearchCompletion) -> String {
        let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subtitle.isEmpty else { return completion.title }
        return "\(completion.title), \(subtitle)"
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

/// Searchable place list backed by MapKit, used to tag a frame's location.
struct LocationSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ResolvedPlace) -> Void

    @State private var model = LocationSearchModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.results.isEmpty {
                    Text(emptyMessage)
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.top, AppTheme.Spacing.xl)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.results.enumerated()), id: \.offset) { index, completion in
                            if index > 0 {
                                HairlineRule()
                            }
                            Button {
                                select(completion)
                            } label: {
                                resultRow(completion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
            .instrumentScreen()
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search places")
            .onChange(of: query) { _, text in
                model.search(text)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppType.body)
                }
            }
        }
        .instrumentSheetChrome()
    }

    private var emptyMessage: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Search for a place to tag this frame."
            : "No matches."
    }

    private func resultRow(_ completion: MKLocalSearchCompletion) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            LucideIcon(.mapPin)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(completion.title)
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .contentShape(Rectangle())
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            let place = await model.resolve(completion)
            onSelect(place)
            dismiss()
        }
    }
}
