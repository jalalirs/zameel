import SwiftUI

struct TripsListView: View {
    @EnvironmentObject var session: Session
    @State private var trips: [Trip] = []
    @State private var error: String?
    @State private var showNewTrip = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error {
                        Text(error).foregroundStyle(.red).padding()
                    }
                    if trips.isEmpty && error == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "airplane.departure")
                                .font(.system(size: 44))
                                .foregroundStyle(Style.hero)
                            Text("No trips yet").font(.headline)
                            Text("Tap + to plan your first one — as a full budget tracker or just a simple itinerary.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 120)
                        .padding(.horizontal, 40)
                    }
                    ForEach(trips) { trip in
                        NavigationLink(value: trip.id) {
                            TripCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trips")
            .navigationDestination(for: String.self) { tripID in
                TripDetailView(store: TripStore(tripID: tripID))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        Avatar(name: APIClient.shared.currentUserName, size: 32)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewTrip = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Style.hero)
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showNewTrip) {
                NewTripView { await load() }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
            }
        }
    }

    private func load() async {
        do {
            if APIClient.shared.currentUserName.isEmpty {
                try? await APIClient.shared.refreshMe()
            }
            trips = try await APIClient.shared.get("trips")
            error = nil
        } catch let e as APIError where e.status == 401 {
            // Stale or revoked token — back to the login screen.
            session.logout()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Label("\(Fmt.shortDate(trip.start_date)) – \(Fmt.shortDate(trip.end_date))",
                          systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack {
                AvatarStack(names: trip.members.map(\.user.name))
                Spacer()
                if trip.budget_enabled {
                    Label(Fmt.money(trip.budget_total, trip.base_currency), systemImage: "chart.pie.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.2), in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Label("Itinerary", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.2), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .background(Style.hero, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.3), radius: 8, y: 4)
    }
}

struct NewTripView: View {
    @Environment(\.dismiss) private var dismiss
    var onDone: () async -> Void

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(7 * 86400)
    @State private var budgetEnabled = true
    @State private var budget = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Trip name", text: $name)
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section {
                    Toggle(isOn: $budgetEnabled) {
                        Label("Track budget & spending", systemImage: "chart.pie")
                    }
                    if budgetEnabled {
                        TextField("Group budget (SAR)", text: $budget)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("Skip this to use Zameel as a pure itinerary — you can enable budgeting later from trip settings.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() {
        Task {
            do {
                let _: Trip = try await APIClient.shared.send("POST", "trips", json: [
                    "name": name,
                    "start_date": Fmt.day.string(from: start),
                    "end_date": Fmt.day.string(from: end),
                    "base_currency": "SAR",
                    "budget_total": Double(budget) ?? 0,
                    "budget_enabled": budgetEnabled,
                    "notes": notes.isEmpty ? nil : notes,
                ])
                await onDone()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
