import SwiftUI

struct CityStopView: View {
    @ObservedObject var store: TripStore
    let cityID: String
    @State private var addSheet: AddSheet?

    enum AddSheet: String, Identifiable {
        case attraction, transport, hotel, expense
        var id: String { rawValue }
    }

    var city: CityStop? { store.cities.first { $0.id == cityID } }

    var body: some View {
        List {
            if let city {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Fmt.shortDate(city.arrive_date)) – \(Fmt.shortDate(city.depart_date))")
                            .font(.subheadline)
                        if let idea = city.main_idea {
                            Text(idea).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Hotels") {
                    ForEach(store.hotels(in: city)) { hotel in
                        NavigationLink {
                            EditCostView(store: store, item: .hotel(hotel))
                        } label: {
                            CostRow(title: hotel.name,
                                    subtitle: "\(Fmt.shortDate(hotel.check_in)) → \(Fmt.shortDate(hotel.check_out))",
                                    item: hotel)
                        }
                    }
                }
                Section("Attractions") {
                    ForEach(store.attractions(in: city).sorted {
                        ($0.planned_date ?? "", $0.planned_time ?? "") < ($1.planned_date ?? "", $1.planned_time ?? "")
                    }) { attraction in
                        NavigationLink {
                            AttractionDetailView(store: store, attractionID: attraction.id)
                        } label: {
                            AttractionRow(attraction: attraction,
                                          photoCount: store.photos(of: attraction).count)
                        }
                    }
                }
                Section("Getting around") {
                    ForEach(store.transport(in: city)) { t in
                        NavigationLink {
                            EditCostView(store: store, item: .transport(t))
                        } label: {
                            CostRow(title: t.description,
                                    subtitle: "\(t.kind) · \(Fmt.shortDate(t.on_date))",
                                    item: t)
                        }
                    }
                }
                Section("Expenses here") {
                    ForEach(store.expenses(in: city)) { e in
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
        .navigationTitle(city?.city ?? "City")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add attraction") { addSheet = .attraction }
                    Button("Add expense") { addSheet = .expense }
                    Button("Add transport") { addSheet = .transport }
                    Button("Add hotel") { addSheet = .hotel }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $addSheet) { which in
            if let city {
                switch which {
                case .attraction: AddAttractionView(store: store, cityID: city.id)
                case .transport: AddTransportView(store: store, cityID: city.id)
                case .hotel: AddHotelView(store: store, city: city)
                case .expense: AddExpenseView(store: store, cityID: city.id)
                }
            }
        }
    }
}

struct AttractionRow: View {
    let attraction: Attraction
    let photoCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(attraction.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                StatusBadge(status: attraction.status)
            }
            HStack(spacing: 8) {
                if let d = attraction.planned_date {
                    Label {
                        Text("\(Fmt.shortDate(d))\(attraction.planned_time.map { " \($0)" } ?? "")")
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
                if photoCount > 0 {
                    Label("\(photoCount)", systemImage: "photo")
                }
                Spacer()
                if attraction.amount > 0 {
                    Text(Fmt.money(attraction.amount, attraction.currency))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
