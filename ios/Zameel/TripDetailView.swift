import SwiftUI

struct TripDetailView: View {
    @StateObject var store: TripStore
    @State private var addSheet: AddSheet?

    enum AddSheet: String, Identifiable {
        case city, leg, expense
        var id: String { rawValue }
    }

    var budgetOn: Bool { store.trip?.budget_enabled ?? true }

    var body: some View {
        List {
            Section {
                TripHero(store: store)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let error = store.error {
                Text(error).foregroundStyle(.red)
            }
            Section {
                if budgetOn, store.budget != nil {
                    NavigationLink {
                        BudgetView(store: store)
                    } label: {
                        Label { Text("Budget & spending") } icon: {
                            IconChip(system: "chart.pie.fill", color: .indigo)
                        }
                    }
                }
                if budgetOn, let b = store.budget, b.pending_count > 0 {
                    NavigationLink {
                        ApprovalsView(store: store)
                    } label: {
                        Label {
                            HStack {
                                Text("Approvals")
                                Spacer()
                                Text("\(b.pending_count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        } icon: {
                            IconChip(system: "clock.badge.exclamationmark", color: .orange)
                        }
                    }
                }
                NavigationLink {
                    MembersView(store: store)
                } label: {
                    Label { Text("Travelers") } icon: {
                        IconChip(system: "person.2.fill", color: .teal)
                    }
                }
            }
            Section("Cities") {
                ForEach(store.cities) { city in
                    NavigationLink {
                        CityStopView(store: store, cityID: city.id)
                    } label: {
                        CityRow(city: city, nights: nights(city))
                    }
                }
            }
            Section("Flights & Trains") {
                ForEach(store.legs) { leg in
                    NavigationLink {
                        EditLegView(store: store, leg: leg)
                    } label: {
                        LegRow(leg: leg)
                    }
                }
            }
            if budgetOn {
                Section("Expenses & Shopping") {
                    ForEach(store.expenses) { e in
                        NavigationLink {
                            EditCostView(store: store, item: .expense(e))
                        } label: {
                            CostRow(title: e.description,
                                    subtitle: "\(e.category) · \(Fmt.shortDate(e.on_date))",
                                    item: e)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if budgetOn {
                        Button("Add expense") { addSheet = .expense }
                    }
                    Button("Add city stop") { addSheet = .city }
                    Button("Add flight / train") { addSheet = .leg }
                    Divider()
                    NavigationLink("Trip settings") {
                        TripSettingsView(store: store)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundStyle(Style.hero)
                }
            }
        }
        .refreshable { await store.loadAll() }
        .task { await store.loadAll() }
        .sheet(item: $addSheet) { which in
            switch which {
            case .expense: AddExpenseView(store: store)
            case .city: AddCityView(store: store)
            case .leg: AddLegView(store: store)
            }
        }
    }

    private func nights(_ city: CityStop) -> Int {
        guard let a = Fmt.day.date(from: city.arrive_date),
              let d = Fmt.day.date(from: city.depart_date) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: a, to: d).day ?? 0)
    }
}

/// Gradient header card: trip name, dates, travelers, and (if budgeting) the
/// remaining amount with a progress bar.
struct TripHero: View {
    @ObservedObject var store: TripStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.trip?.name ?? "Trip")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                if let trip = store.trip {
                    Label("\(Fmt.shortDate(trip.start_date)) – \(Fmt.shortDate(trip.end_date))",
                          systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            AvatarStack(names: store.members.map(\.user.name))
            if store.trip?.budget_enabled == true, let b = store.budget {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(Fmt.money(b.remaining_vs_committed, b.base_currency))
                            .font(.title3.bold())
                            .foregroundStyle(b.remaining_vs_committed < 0 ? Color.yellow : .white)
                    }
                    ProgressView(value: min(b.committed_base, b.budget_total),
                                 total: max(b.budget_total, 1))
                        .tint(.white)
                    HStack {
                        Text("Planned \(Fmt.money(b.committed_base, b.base_currency))")
                        Spacer()
                        Text("Spent \(Fmt.money(b.paid_base, b.base_currency))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .padding(12)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.hero, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.3), radius: 8, y: 4)
    }
}

struct CityRow: View {
    let city: CityStop
    let nights: Int

    var body: some View {
        HStack(spacing: 12) {
            IconChip(system: "building.2.fill", color: .purple)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(city.city).font(.headline)
                    Spacer()
                    Text(nights == 0 ? "day trip" : "\(nights) night\(nights == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(Fmt.shortDate(city.arrive_date)) – \(Fmt.shortDate(city.depart_date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let idea = city.main_idea, !idea.isEmpty {
                    Text(idea).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct LegRow: View {
    let leg: TravelLeg

    var kindIcon: String {
        switch leg.kind {
        case "flight": "airplane"
        case "train": "tram.fill"
        case "bus": "bus.fill"
        default: "ferry.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconChip(system: kindIcon, color: .blue)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(leg.from_city) → \(leg.to_city)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    StatusBadge(status: leg.status)
                }
                HStack {
                    if let d = leg.depart_at {
                        Text(String(d.prefix(10))).font(.caption).foregroundStyle(.secondary)
                    }
                    ApprovalBadge(approval: leg.approval)
                    Spacer()
                    Text(Fmt.money(leg.totalAmount, leg.currency)).font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CostRow: View {
    let title: String
    let subtitle: String
    let item: any CostItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                StatusBadge(status: item.status)
            }
            HStack(spacing: 6) {
                Image(systemName: item.scopeIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                ApprovalBadge(approval: item.approval)
                Spacer()
                Text(item.units > 1
                     ? "\(Int(item.units)) × \(Fmt.money(item.amount, item.currency))"
                     : Fmt.money(item.totalAmount, item.currency))
                    .font(.caption)
            }
        }
    }
}

struct StatusBadge: View {
    let status: String

    var color: Color {
        switch status {
        case "paid": .green
        case "booked": .blue
        default: .orange
        }
    }

    var body: some View {
        Text(status)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
