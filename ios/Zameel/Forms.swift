import SwiftUI

// ---- shared cost-field editing ----

struct CostFields {
    var amount = ""
    var units = "1"
    var currency = "JPY"
    var fx = ""
    var status = "planned"
    var paidAmount = ""
    var bookingRef = ""
    var notes = ""
    var scope = "group"
    var participants: Set<String> = []
    var bookingUrl = ""
    var hasBookingOpens = false
    var bookingOpens = Date()

    static let currencies = ["SAR", "JPY", "KRW", "USD", "EUR"]
    static let defaultFX: [String: Double] = ["SAR": 1, "JPY": 0.025, "KRW": 0.0027, "USD": 3.75, "EUR": 4.1]

    init() {}

    init(from item: any CostItem) {
        amount = item.amount == 0 ? "" : String(item.amount)
        units = item.units == 1 ? "1" : String(item.units)
        currency = item.currency
        fx = String(item.fx_to_base)
        status = item.status
        if let p = item.paid_amount { paidAmount = String(p) }
        scope = item.scope
        participants = Set(item.participant_ids ?? [])
        bookingUrl = item.booking_url ?? ""
        if let opens = item.booking_opens, let d = Fmt.day.date(from: opens) {
            hasBookingOpens = true
            bookingOpens = d
        }
    }

    var fxValue: Double {
        Double(fx) ?? CostFields.defaultFX[currency] ?? 1
    }

    var totalPreview: Double { (Double(amount) ?? 0) * (Double(units) ?? 1) }

    var json: [String: Any?] {
        [
            "amount": Double(amount) ?? 0,
            "units": Double(units) ?? 1,
            "currency": currency,
            "fx_to_base": fxValue,
            "status": status,
            "paid_amount": Double(paidAmount),
            "booking_ref": bookingRef.isEmpty ? nil : bookingRef,
            "notes": notes.isEmpty ? nil : notes,
            "scope": scope,
            "participant_ids": scope == "shared" ? Array(participants) : nil,
            "booking_url": bookingUrl.isEmpty ? nil : bookingUrl,
            "booking_opens": hasBookingOpens ? Fmt.day.string(from: bookingOpens) : nil,
        ]
    }
}

struct CostFieldsSection: View {
    @Binding var cost: CostFields

    var body: some View {
        Section("Cost") {
            HStack {
                TextField("Price per unit", text: $cost.amount)
                    .keyboardType(.decimalPad)
                Picker("", selection: $cost.currency) {
                    ForEach(CostFields.currencies, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .onChange(of: cost.currency) { _, new in
                    cost.fx = String(CostFields.defaultFX[new] ?? 1)
                }
            }
            UnitsRow(cost: $cost)
            TextField("FX rate to SAR", text: $cost.fx)
                .keyboardType(.decimalPad)
            Picker("Status", selection: $cost.status) {
                Text("Planned").tag("planned")
                Text("Booked").tag("booked")
                Text("Paid").tag("paid")
            }
            .pickerStyle(.segmented)
            if cost.status == "paid" {
                TextField("Actual total paid (optional)", text: $cost.paidAmount)
                    .keyboardType(.decimalPad)
            }
            TextField("Booking reference", text: $cost.bookingRef)
            TextField("Notes", text: $cost.notes, axis: .vertical)
        }
    }
}

struct UnitsRow: View {
    @Binding var cost: CostFields

    private var unitsValue: Double { Double(cost.units) ?? 1 }

    private var unitsBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(cost.units) ?? 1 },
            set: { (v: Double) in
                cost.units = v == v.rounded() ? String(Int(v)) : String(v)
            }
        )
    }

    var body: some View {
        HStack {
            Text("Units")
            Spacer()
            TextField("1", text: $cost.units)
                .keyboardType(.decimalPad)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
            Stepper("", value: unitsBinding, in: 1...99)
                .labelsHidden()
        }
        if unitsValue > 1, cost.totalPreview > 0 {
            LabeledContent("Total") {
                Text(Fmt.money(cost.totalPreview, cost.currency)).bold()
            }
        }
    }
}

/// Whose money is this? Group pot, one person's own, or split between people.
struct ScopeSection: View {
    @ObservedObject var store: TripStore
    @Binding var cost: CostFields

    var body: some View {
        Section("Who pays") {
            Picker("Scope", selection: $cost.scope) {
                Label("Group", systemImage: "person.3").tag("group")
                Label("Personal", systemImage: "person").tag("personal")
                Label("Split", systemImage: "person.2").tag("shared")
            }
            .pickerStyle(.segmented)
            if cost.scope == "shared" {
                ForEach(store.members) { m in
                    Button {
                        if cost.participants.contains(m.user.id) {
                            cost.participants.remove(m.user.id)
                        } else {
                            cost.participants.insert(m.user.id)
                        }
                    } label: {
                        HStack {
                            Avatar(name: m.user.name, size: 26)
                            Text(m.user.name).foregroundStyle(.primary)
                            Spacer()
                            if cost.participants.contains(m.user.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else if cost.scope == "group", !store.isLeader {
                Label("Will wait for a trip leader's approval", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ---- generic form scaffold ----

struct FormSheet<Content: View>: View {
    let title: String
    let saveDisabled: Bool
    let onSave: () async throws -> Void
    let onDelete: (() async throws -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                content()
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if onDelete != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            run { try await onDelete?() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { run(onSave) }.disabled(saveDisabled)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        Task {
            do {
                try await op()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// ---- which cost item is being edited ----

enum CostRef: Identifiable {
    case leg(TravelLeg)
    case hotel(Hotel)
    case attraction(Attraction)
    case transport(LocalTransport)
    case expense(Expense)

    var id: String { path }

    var path: String {
        switch self {
        case .leg(let l): "legs/\(l.id)"
        case .hotel(let h): "hotels/\(h.id)"
        case .attraction(let a): "attractions/\(a.id)"
        case .transport(let t): "transport/\(t.id)"
        case .expense(let e): "expenses/\(e.id)"
        }
    }

    var title: String {
        switch self {
        case .leg(let l): "\(l.from_city) → \(l.to_city)"
        case .hotel(let h): h.name
        case .attraction(let a): a.name
        case .transport(let t): t.description
        case .expense(let e): e.description
        }
    }

    var item: any CostItem {
        switch self {
        case .leg(let l): l
        case .hotel(let h): h
        case .attraction(let a): a
        case .transport(let t): t
        case .expense(let e): e
        }
    }
}

/// Edit the money side of any item: amount, status, actual paid amount.
/// This is the main "during the trip" workflow — mark things paid as you go.
struct EditCostView: View {
    @ObservedObject var store: TripStore
    let item: CostRef
    @State private var cost: CostFields
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    init(store: TripStore, item: CostRef) {
        self.store = store
        self.item = item
        _cost = State(initialValue: CostFields(from: item.item))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(item.title).font(.headline)
                    Spacer()
                    ApprovalBadge(approval: item.item.approval)
                }
                if let payer = store.memberName(item.item.paid_by) {
                    Label("Added by \(payer)", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            BookingInfoSection(title: item.title, item: item.item)
            CostFieldsSection(cost: $cost)
            BookingFieldsSection(cost: $cost)
            ScopeSection(store: store, cost: $cost)
            AttachmentsSection(store: store, itemPath: item.path)
            approvalSection
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await APIClient.shared.delete("trips/\(store.tripID)/\(item.path)")
                        await store.loadAll()
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
    }

    @ViewBuilder
    private var approvalSection: some View {
        let it = item.item
        if it.approval == "pending" && store.isLeader {
            Section("Waiting for a leader") {
                Button { decide("approve") } label: {
                    Label("Approve into group budget", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button { decide("reject") } label: {
                    Label("Keep it personal", systemImage: "hand.raised.fill")
                        .foregroundStyle(.red)
                }
            }
        } else if it.scope == "personal" || it.approval == "rejected" {
            Section {
                Button { decide("request") } label: {
                    Label(store.isLeader ? "Move into group budget"
                                         : "Ask leaders to include in group budget",
                          systemImage: "person.3")
                }
            }
        }
    }

    private func decide(_ action: String) {
        Task {
            do {
                struct Ignore: Decodable {}
                let _: Ignore = try await APIClient.shared.send(
                    "POST", "trips/\(store.tripID)/\(item.path)/approval", json: ["action": action])
                await store.loadAll()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        Task {
            do {
                struct Ignore: Decodable {}
                let _: Ignore = try await APIClient.shared.send(
                    "PATCH", "trips/\(store.tripID)/\(item.path)",
                    json: cost.json.filter { $0.key != "booking_ref" && $0.key != "notes" })
                await store.loadAll()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// ---- add forms ----

struct AddExpenseView: View {
    @ObservedObject var store: TripStore
    var cityID: String? = nil
    @State private var description = ""
    @State private var category = "food"
    @State private var date = Date()
    @State private var cost = CostFields()

    var body: some View {
        FormSheet(title: "New Expense", saveDisabled: description.isEmpty, onSave: {
            let _: Expense = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/expenses",
                json: cost.json.merging([
                    "description": description,
                    "category": category,
                    "on_date": Fmt.day.string(from: date),
                    "city_stop_id": cityID,
                    "status": "paid",
                ]) { _, b in b })
            await store.loadAll()
        }, onDelete: nil) {
            Section {
                TextField("What did you pay for?", text: $description)
                Picker("Category", selection: $category) {
                    Text("Food").tag("food")
                    Text("Shopping").tag("shopping")
                    Text("Misc").tag("misc")
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            CostFieldsSection(cost: $cost)
            ScopeSection(store: store, cost: $cost)
        }
    }
}

struct AddAttractionView: View {
    @ObservedObject var store: TripStore
    let cityID: String
    @State private var name = ""
    @State private var date = Date()
    @State private var time = ""
    @State private var lat = ""
    @State private var lon = ""
    @State private var cost = CostFields()

    var body: some View {
        FormSheet(title: "New Attraction", saveDisabled: name.isEmpty, onSave: {
            let _: Attraction = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/attractions",
                json: cost.json.merging([
                    "name": name,
                    "city_stop_id": cityID,
                    "planned_date": Fmt.day.string(from: date),
                    "planned_time": time.isEmpty ? nil : time,
                    "lat": Double(lat),
                    "lon": Double(lon),
                ]) { _, b in b })
            await store.loadAll()
        }, onDelete: nil) {
            Section {
                TextField("Name", text: $name)
                DatePicker("Planned date", selection: $date, displayedComponents: .date)
                TextField("Time (e.g. 09:30)", text: $time)
                HStack {
                    TextField("Latitude", text: $lat).keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $lon).keyboardType(.numbersAndPunctuation)
                }
            } footer: {
                Text("Coordinates let Zameel match your photos to this attraction automatically.")
            }
            CostFieldsSection(cost: $cost)
        }
    }
}

struct AddTransportView: View {
    @ObservedObject var store: TripStore
    let cityID: String
    @State private var description = ""
    @State private var kind = "taxi"
    @State private var date = Date()
    @State private var cost = CostFields()

    var body: some View {
        FormSheet(title: "New Transport", saveDisabled: description.isEmpty, onSave: {
            let _: LocalTransport = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/transport",
                json: cost.json.merging([
                    "description": description,
                    "kind": kind,
                    "city_stop_id": cityID,
                    "on_date": Fmt.day.string(from: date),
                ]) { _, b in b })
            await store.loadAll()
        }, onDelete: nil) {
            Section {
                TextField("Description (e.g. Taxi to Gion)", text: $description)
                Picker("Kind", selection: $kind) {
                    Text("Taxi").tag("taxi")
                    Text("Metro").tag("metro")
                    Text("Bus").tag("bus")
                    Text("IC card").tag("ic_card")
                    Text("Transfer").tag("transfer")
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            CostFieldsSection(cost: $cost)
        }
    }
}

struct AddHotelView: View {
    @ObservedObject var store: TripStore
    let city: CityStop
    @State private var name = ""
    @State private var address = ""
    @State private var checkIn = Date()
    @State private var checkOut = Date()
    @State private var cost = CostFields()

    init(store: TripStore, city: CityStop) {
        self.store = store
        self.city = city
        _checkIn = State(initialValue: Fmt.day.date(from: city.arrive_date) ?? Date())
        _checkOut = State(initialValue: Fmt.day.date(from: city.depart_date) ?? Date())
    }

    var body: some View {
        FormSheet(title: "New Hotel", saveDisabled: name.isEmpty, onSave: {
            let _: Hotel = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/hotels",
                json: cost.json.merging([
                    "name": name,
                    "address": address.isEmpty ? nil : address,
                    "city_stop_id": city.id,
                    "check_in": Fmt.day.string(from: checkIn),
                    "check_out": Fmt.day.string(from: checkOut),
                ]) { _, b in b })
            await store.loadAll()
        }, onDelete: nil) {
            Section {
                TextField("Hotel name", text: $name)
                TextField("Address", text: $address)
                DatePicker("Check-in", selection: $checkIn, displayedComponents: .date)
                DatePicker("Check-out", selection: $checkOut, displayedComponents: .date)
            }
            CostFieldsSection(cost: $cost)
        }
    }
}

struct AddCityView: View {
    @ObservedObject var store: TripStore
    @State private var city = ""
    @State private var country = ""
    @State private var arrive = Date()
    @State private var depart = Date()
    @State private var idea = ""

    var body: some View {
        FormSheet(title: "New City Stop", saveDisabled: city.isEmpty, onSave: {
            let _: CityStop = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/cities",
                json: [
                    "city": city,
                    "country": country.isEmpty ? nil : country,
                    "arrive_date": Fmt.day.string(from: arrive),
                    "depart_date": Fmt.day.string(from: depart),
                    "order_index": store.cities.count,
                    "main_idea": idea.isEmpty ? nil : idea,
                ])
            await store.loadAll()
        }, onDelete: nil) {
            TextField("City", text: $city)
            TextField("Country", text: $country)
            DatePicker("Arrive", selection: $arrive, displayedComponents: .date)
            DatePicker("Depart", selection: $depart, displayedComponents: .date)
            TextField("Main idea (e.g. Dotonbori + USJ)", text: $idea, axis: .vertical)
        }
    }
}

struct AddLegView: View {
    @ObservedObject var store: TripStore
    @State private var kind = "flight"
    @State private var from = ""
    @State private var to = ""
    @State private var carrier = ""
    @State private var departAt = Date()
    @State private var cost = CostFields()

    var body: some View {
        FormSheet(title: "New Flight / Train", saveDisabled: from.isEmpty || to.isEmpty, onSave: {
            let iso = ISO8601DateFormatter()
            let _: TravelLeg = try await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/legs",
                json: cost.json.merging([
                    "kind": kind,
                    "from_city": from,
                    "to_city": to,
                    "carrier": carrier.isEmpty ? nil : carrier,
                    "depart_at": iso.string(from: departAt),
                ]) { _, b in b })
            await store.loadAll()
        }, onDelete: nil) {
            Section {
                Picker("Kind", selection: $kind) {
                    Text("Flight").tag("flight")
                    Text("Train").tag("train")
                    Text("Bus").tag("bus")
                    Text("Ferry").tag("ferry")
                }
                .pickerStyle(.segmented)
                TextField("From", text: $from)
                TextField("To", text: $to)
                TextField("Carrier", text: $carrier)
                DatePicker("Departure", selection: $departAt)
            }
            CostFieldsSection(cost: $cost)
        }
    }
}

struct EditLegView: View {
    @ObservedObject var store: TripStore
    let leg: TravelLeg
    @State private var cost: CostFields
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    init(store: TripStore, leg: TravelLeg) {
        self.store = store
        self.leg = leg
        _cost = State(initialValue: CostFields(from: leg))
    }

    var body: some View {
        Form {
            Section {
                LegRow(leg: leg)
                if let notes = leg.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
            }
            BookingInfoSection(title: "\(leg.from_city) → \(leg.to_city)", item: leg)
            CostFieldsSection(cost: $cost)
            BookingFieldsSection(cost: $cost)
            ScopeSection(store: store, cost: $cost)
            AttachmentsSection(store: store, itemPath: "legs/\(leg.id)")
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("\(leg.from_city) → \(leg.to_city)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        do {
                            let _: TravelLeg = try await APIClient.shared.send(
                                "PATCH", "trips/\(store.tripID)/legs/\(leg.id)",
                                json: cost.json.filter { $0.key != "booking_ref" && $0.key != "notes" })
                            await store.loadAll()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
