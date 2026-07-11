import SwiftUI

// ---- profile & settings ----

struct ProfileView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseURL") private var baseURL = "https://jalalirs.tailedf721.ts.net/zameel"
    @State private var name = APIClient.shared.currentUserName
    @State private var newPassword = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Avatar(name: name, size: 72)
                        Text(name).font(.title3.bold())
                        Text(APIClient.shared.currentUserEmail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Your name") {
                    TextField("Name", text: $name)
                }
                Section("Change password") {
                    SecureField("New password (leave empty to keep)", text: $newPassword)
                }
                Section("Server") {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                }
                if let message {
                    Section { Text(message).foregroundStyle(isError ? .red : .green) }
                }
                Section {
                    Button("Save changes") { save() }
                        .frame(maxWidth: .infinity)
                    Button("Sign out", role: .destructive) {
                        session.logout()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                var body: [String: Any?] = ["name": name]
                if !newPassword.isEmpty { body["password"] = newPassword }
                let _: UserOut = try await APIClient.shared.send("PATCH", "auth/me", json: body)
                try await APIClient.shared.refreshMe()
                message = "Saved"
                isError = false
                newPassword = ""
            } catch {
                message = error.localizedDescription
                isError = true
            }
        }
    }
}

// ---- trip members ----

struct MembersView: View {
    @ObservedObject var store: TripStore
    @State private var inviteEmail = ""
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(store.members) { m in
                    MemberRow(store: store, member: m)
                }
            } footer: {
                Text("Leaders approve group expenses. Roles are open — anyone can promote or step down; the app trusts the group.")
            }
            Section("Invite someone") {
                HStack {
                    TextField("Email of an existing account", text: $inviteEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Invite") { invite() }
                        .buttonStyle(.borderedProminent)
                        .disabled(inviteEmail.isEmpty)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Travelers")
    }

    private func invite() {
        Task {
            do {
                let _: MemberOut = try await APIClient.shared.send(
                    "POST", "trips/\(store.tripID)/members", json: ["email": inviteEmail])
                inviteEmail = ""
                error = nil
                await store.loadAll()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct MemberRow: View {
    @ObservedObject var store: TripStore
    let member: MemberOut
    @State private var budgetText = ""

    var isSelf: Bool { member.user.id == APIClient.shared.currentUserID }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Avatar(name: member.user.name, size: 38)
                VStack(alignment: .leading) {
                    Text(member.user.name + (isSelf ? " (you)" : ""))
                        .font(.subheadline.weight(.semibold))
                    Text(member.user.email).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(member.role == "leader" ? "Make member" : "Make leader") {
                        patch(["role": member.role == "leader" ? "member" : "leader"])
                    }
                    Button("Remove from trip", role: .destructive) { remove() }
                } label: {
                    Text(member.role)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(member.role == "leader" ? Color.indigo.opacity(0.15) : Color.gray.opacity(0.12))
                        .foregroundStyle(member.role == "leader" ? Color.indigo : Color.secondary)
                        .clipShape(Capsule())
                }
            }
            // Personal budgets are private: you only ever see and edit your own.
            if isSelf, store.trip?.budget_enabled == true {
                HStack {
                    Text("Your personal budget").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TextField("none", text: $budgetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onSubmit { patch(["personal_budget": Double(budgetText)]) }
                    Text("SAR").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            if isSelf, let b = store.budget?.members.first(where: { $0.user.id == member.user.id }),
               let pb = b.personal_budget {
                budgetText = String(Int(pb))
            }
        }
    }

    private func patch(_ body: [String: Any?]) {
        Task {
            struct Ignore: Decodable {}
            let _: Ignore? = try? await APIClient.shared.send(
                "PATCH", "trips/\(store.tripID)/members/\(member.id)", json: body)
            await store.loadAll()
        }
    }

    private func remove() {
        Task {
            try? await APIClient.shared.delete("trips/\(store.tripID)/members/\(member.id)")
            await store.loadAll()
        }
    }
}

// ---- pending approvals ----

struct ApprovalsView: View {
    @ObservedObject var store: TripStore

    var body: some View {
        List {
            if store.pendingRefs.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.seal",
                                       description: Text("Nothing is waiting for approval."))
            } else {
                Section {
                    ForEach(store.pendingRefs, id: \.path) { ref in
                        PendingRow(store: store, ref: ref)
                    }
                } footer: {
                    if !store.isLeader {
                        Text("Only trip leaders can approve or reject.")
                    }
                }
            }
        }
        .navigationTitle("Approvals")
    }

    private func decide(_ ref: CostRef, _ action: String) {
        Task {
            struct Ignore: Decodable {}
            let _: Ignore? = try? await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/\(ref.path)/approval", json: ["action": action])
            await store.loadAll()
        }
    }
}

struct PendingRow: View {
    @ObservedObject var store: TripStore
    let ref: CostRef

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ref.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.money(ref.item.totalAmount, ref.item.currency))
                    .font(.subheadline)
            }
            if let payer = store.memberName(ref.item.paid_by) {
                Text("Added by \(payer)").font(.caption).foregroundStyle(.secondary)
            }
            if store.isLeader {
                HStack {
                    Button {
                        decide("approve")
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button {
                        decide("reject")
                    } label: {
                        Label("Keep personal", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func decide(_ action: String) {
        Task {
            struct Ignore: Decodable {}
            let _: Ignore? = try? await APIClient.shared.send(
                "POST", "trips/\(store.tripID)/\(ref.path)/approval", json: ["action": action])
            await store.loadAll()
        }
    }
}

// ---- trip settings ----

struct TripSettingsView: View {
    @ObservedObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var budgetEnabled = true
    @State private var budgetTotal = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Name", text: $name)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            Section {
                Toggle(isOn: $budgetEnabled) {
                    Label("Track budget & spending", systemImage: "chart.pie")
                }
                if budgetEnabled {
                    HStack {
                        Text("Group budget")
                        Spacer()
                        TextField("0", text: $budgetTotal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text(store.trip?.base_currency ?? "SAR")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Turn this off to use the trip as a pure itinerary — no budgets, no amounts. You can turn it back on anytime; nothing is deleted.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Trip settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            guard !loaded, let trip = store.trip else { return }
            loaded = true
            name = trip.name
            budgetEnabled = trip.budget_enabled
            budgetTotal = trip.budget_total == 0 ? "" : String(Int(trip.budget_total))
            notes = trip.notes ?? ""
        }
    }

    private func save() {
        Task {
            do {
                let _: Trip = try await APIClient.shared.send("PATCH", "trips/\(store.tripID)", json: [
                    "name": name,
                    "budget_enabled": budgetEnabled,
                    "budget_total": Double(budgetTotal) ?? 0,
                    "notes": notes.isEmpty ? nil : notes,
                ])
                await store.loadAll()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
