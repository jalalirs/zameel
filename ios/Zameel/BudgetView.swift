import SwiftUI

struct BudgetView: View {
    @ObservedObject var store: TripStore

    private let labels: [String: (String, String)] = [
        "travel": ("Flights & Trains", "airplane"),
        "hotels": ("Hotels", "bed.double.fill"),
        "attractions": ("Attractions", "ticket.fill"),
        "transport": ("Local transport", "car.fill"),
        "expenses": ("Food & Shopping", "fork.knife"),
    ]

    var body: some View {
        List {
            if let b = store.budget {
                Section("Group budget") {
                    row("Total budget", b.budget_total, b.base_currency, bold: true)
                    row("Planned + booked + paid", b.committed_base, b.base_currency)
                    row("Actually spent so far", b.paid_base, b.base_currency)
                    row("Left if all plans happen", b.remaining_vs_committed, b.base_currency,
                        color: b.remaining_vs_committed < 0 ? .red : .green)
                }
                if b.pending_count > 0 {
                    Section {
                        NavigationLink {
                            ApprovalsView(store: store)
                        } label: {
                            Label {
                                Text("\(b.pending_count) item\(b.pending_count == 1 ? "" : "s") waiting for approval")
                            } icon: {
                                IconChip(system: "clock.badge.exclamationmark", color: .orange, size: 30)
                            }
                        }
                    }
                }
                Section("By category") {
                    ForEach(b.categories) { cat in
                        let (label, icon) = labels[cat.category] ?? (cat.category, "circle")
                        HStack(spacing: 12) {
                            IconChip(system: icon, color: Style.categoryColor(cat.category), size: 30)
                            Text(label)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Fmt.money(cat.planned_base, b.base_currency))
                                    .font(.subheadline.weight(.medium))
                                if cat.paid_base > 0 {
                                    Text("paid \(Fmt.money(cat.paid_base, b.base_currency))")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                // Personal money is private — the server only sends your own numbers.
                if let mine = b.members.first(where: { $0.user.id == APIClient.shared.currentUserID }) {
                    Section("Your spending") {
                        MemberBudgetRow(m: mine, currency: b.base_currency)
                    }
                }
            }
        }
        .navigationTitle("Budget")
        .refreshable { await store.loadAll() }
    }

    private func row(_ label: String, _ value: Double, _ currency: String,
                     bold: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Fmt.money(value, currency))
                .font(bold ? .body.bold() : .body)
                .foregroundStyle(color)
        }
    }
}

/// Your own money: personal items + your share of split items (+ anything a
/// leader kept out of the group pot). Never shown for other travelers.
struct MemberBudgetRow: View {
    let m: MemberBudget
    let currency: String

    private var spent: Double { m.personal_base ?? 0 }
    private var paid: Double { m.personal_paid_base ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Avatar(name: m.user.name, size: 32)
                Text("Personal + your share of splits")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.money(spent, currency))
                    .font(.subheadline.bold())
            }
            if let pb = m.personal_budget, pb > 0 {
                ProgressView(value: min(spent, pb), total: max(pb, 1))
                    .tint(spent > pb ? .red : .indigo)
                HStack {
                    Text("of \(Fmt.money(pb, currency)) personal budget")
                    Spacer()
                    if paid > 0 {
                        Text("paid \(Fmt.money(paid, currency))")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if paid > 0 {
                Text("paid \(Fmt.money(paid, currency))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
