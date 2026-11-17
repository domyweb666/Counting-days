import Foundation
import MapKit
import Observation
import CalendarCore

/// 地點欄打字時，問 Apple 地圖有哪些地方對得上。選了一個再去查它的座標。
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    /// 一次最多列幾個建議
    static let maxResults = 5

    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// 欄位裡的字變了就丟進來。空的就清掉建議。
    func update(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func clear() {
        completer.cancel()
        results = []
    }

    /// 查選到的那一個的座標。查不到回傳 nil，表單就照打的字存。
    func resolve(_ completion: MKLocalSearchCompletion) async -> PlacePoint? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return PlacePoint(
            name: completion.title,
            address: completion.subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(Self.maxResults))
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
