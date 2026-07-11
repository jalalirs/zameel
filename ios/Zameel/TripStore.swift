import SwiftUI

/// Holds everything for one open trip and refreshes it from the API.
@MainActor
final class TripStore: ObservableObject {
    let tripID: String
    @Published var trip: Trip?
    @Published var cities: [CityStop] = []
    @Published var legs: [TravelLeg] = []
    @Published var hotels: [Hotel] = []
    @Published var attractions: [Attraction] = []
    @Published var transport: [LocalTransport] = []
    @Published var expenses: [Expense] = []
    @Published var budget: BudgetSummary?
    @Published var photos: [Photo] = []
    @Published var error: String?

    init(tripID: String) {
        self.tripID = tripID
    }

    func loadAll() async {
        do {
            async let trip: Trip = APIClient.shared.get("trips/\(tripID)")
            async let cities: [CityStop] = APIClient.shared.get("trips/\(tripID)/cities")
            async let legs: [TravelLeg] = APIClient.shared.get("trips/\(tripID)/legs")
            async let hotels: [Hotel] = APIClient.shared.get("trips/\(tripID)/hotels")
            async let attractions: [Attraction] = APIClient.shared.get("trips/\(tripID)/attractions")
            async let transport: [LocalTransport] = APIClient.shared.get("trips/\(tripID)/transport")
            async let expenses: [Expense] = APIClient.shared.get("trips/\(tripID)/expenses")
            async let budget: BudgetSummary = APIClient.shared.get("trips/\(tripID)/budget")
            async let photos: [Photo] = APIClient.shared.get("trips/\(tripID)/photos")
            self.trip = try await trip
            self.cities = try await cities
            self.legs = try await legs
            self.hotels = try await hotels
            self.attractions = try await attractions
            self.transport = try await transport
            self.expenses = try await expenses
            self.budget = try await budget
            self.photos = try await photos
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    var members: [MemberOut] { trip?.members ?? [] }

    var isLeader: Bool {
        members.first { $0.user.id == APIClient.shared.currentUserID }?.role == "leader"
    }

    func memberName(_ userID: String?) -> String? {
        members.first { $0.user.id == userID }?.user.name
    }

    /// Everything waiting for a leader's decision, across all item types.
    var pendingRefs: [CostRef] {
        var refs: [CostRef] = []
        refs += legs.filter { $0.approval == "pending" }.map { .leg($0) }
        refs += hotels.filter { $0.approval == "pending" }.map { .hotel($0) }
        refs += attractions.filter { $0.approval == "pending" }.map { .attraction($0) }
        refs += transport.filter { $0.approval == "pending" }.map { .transport($0) }
        refs += expenses.filter { $0.approval == "pending" }.map { .expense($0) }
        return refs
    }

    func hotels(in city: CityStop) -> [Hotel] { hotels.filter { $0.city_stop_id == city.id } }
    func attractions(in city: CityStop) -> [Attraction] { attractions.filter { $0.city_stop_id == city.id } }
    func transport(in city: CityStop) -> [LocalTransport] { transport.filter { $0.city_stop_id == city.id } }
    func expenses(in city: CityStop) -> [Expense] { expenses.filter { $0.city_stop_id == city.id } }
    func photos(of attraction: Attraction) -> [Photo] { photos.filter { $0.attraction_id == attraction.id } }
}
