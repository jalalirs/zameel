import SwiftUI

@main
struct ZameelApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            // Debug hook: jump straight to one attraction (used by tooling).
            if let tripID = ProcessInfo.processInfo.environment["OPEN_TRIP"] {
                DebugRoot(store: TripStore(tripID: tripID),
                          attractionID: ProcessInfo.processInfo.environment["OPEN_ATTRACTION"],
                          cityID: ProcessInfo.processInfo.environment["OPEN_CITY"],
                          view: ProcessInfo.processInfo.environment["OPEN_VIEW"])
            } else if session.loggedIn {
                TripsListView()
                    .environmentObject(session)
            } else {
                LoginView()
                    .environmentObject(session)
            }
        }
    }
}

/// Tooling entry point: jump straight to one screen via env vars
/// (screenshots, debugging). Never active on a normal launch.
struct DebugRoot: View {
    @StateObject var store: TripStore
    let attractionID: String?
    let cityID: String?
    let view: String?

    var body: some View {
        NavigationStack {
            if let attractionID {
                AttractionDetailView(store: store, attractionID: attractionID)
            } else if let cityID {
                CityStopView(store: store, cityID: cityID)
            } else if view == "budget" {
                BudgetView(store: store)
            } else {
                TripDetailView(store: store)
            }
        }
        .task { await store.loadAll() }
    }
}

@MainActor
final class Session: ObservableObject {
    @Published var loggedIn: Bool = APIClient.shared.token != nil

    func logout() {
        APIClient.shared.token = nil
        loggedIn = false
    }
}
