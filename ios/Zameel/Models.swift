import Foundation

// Mirrors of the backend schemas. Dates come as "yyyy-MM-dd" strings for Date
// fields and ISO8601 for datetimes; keep them as strings and format at the edge.

struct TokenOut: Codable {
    let access_token: String
}

struct UserOut: Codable, Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
}

struct MemberOut: Codable, Identifiable, Hashable {
    let id: String
    var role: String
    let user: UserOut
}

struct Trip: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var start_date: String
    var end_date: String
    var base_currency: String
    var budget_total: Double
    var budget_enabled: Bool
    var notes: String?
    let created_by: String
    var members: [MemberOut]
}

struct CityStop: Codable, Identifiable, Hashable {
    let id: String
    let trip_id: String
    var city: String
    var country: String?
    var arrive_date: String
    var depart_date: String
    var order_index: Int
    var main_idea: String?
}

protocol CostItem {
    var amount: Double { get }
    var units: Double { get }
    var currency: String { get }
    var fx_to_base: Double { get }
    var status: String { get }
    var paid_amount: Double? { get }
    var scope: String { get }
    var approval: String { get }
    var participant_ids: [String]? { get }
    var paid_by: String? { get }
    var booking_url: String? { get }
    var booking_opens: String? { get }
}

extension CostItem {
    /// Planned total in the item's own currency (unit price × units).
    var totalAmount: Double { amount * units }

    /// Cost converted to the trip's base currency; actual once paid.
    var baseAmount: Double {
        let a = (status == "paid" && paid_amount != nil) ? paid_amount! : totalAmount
        return a * fx_to_base
    }

    var scopeIcon: String {
        switch scope {
        case "personal": "person"
        case "shared": "person.2"
        default: "person.3"
        }
    }
}

struct TravelLeg: Codable, Identifiable, Hashable, CostItem {
    let id: String
    let trip_id: String
    var kind: String
    var carrier: String?
    var from_city: String
    var to_city: String
    var depart_at: String?
    var arrive_at: String?
    var amount: Double
    var units: Double
    var currency: String
    var fx_to_base: Double
    var status: String
    var paid_amount: Double?
    var booking_ref: String?
    var notes: String?
    var scope: String
    var participant_ids: [String]?
    var approval: String
    var paid_by: String?
    var booking_url: String?
    var booking_opens: String?
}

struct Hotel: Codable, Identifiable, Hashable, CostItem {
    let id: String
    let trip_id: String
    var city_stop_id: String?
    var name: String
    var address: String?
    var check_in: String
    var check_out: String
    var amount: Double
    var units: Double
    var currency: String
    var fx_to_base: Double
    var status: String
    var paid_amount: Double?
    var booking_ref: String?
    var notes: String?
    var scope: String
    var participant_ids: [String]?
    var approval: String
    var paid_by: String?
    var booking_url: String?
    var booking_opens: String?
}

struct Attraction: Codable, Identifiable, Hashable, CostItem {
    let id: String
    let trip_id: String
    var city_stop_id: String?
    var name: String
    var planned_date: String?
    var planned_time: String?
    var lat: Double?
    var lon: Double?
    var amount: Double
    var units: Double
    var currency: String
    var fx_to_base: Double
    var status: String
    var paid_amount: Double?
    var booking_ref: String?
    var notes: String?
    var scope: String
    var participant_ids: [String]?
    var approval: String
    var paid_by: String?
    var booking_url: String?
    var booking_opens: String?
}

struct LocalTransport: Codable, Identifiable, Hashable, CostItem {
    let id: String
    let trip_id: String
    var city_stop_id: String?
    var kind: String
    var description: String
    var on_date: String?
    var amount: Double
    var units: Double
    var currency: String
    var fx_to_base: Double
    var status: String
    var paid_amount: Double?
    var booking_ref: String?
    var notes: String?
    var scope: String
    var participant_ids: [String]?
    var approval: String
    var paid_by: String?
    var booking_url: String?
    var booking_opens: String?
}

struct Expense: Codable, Identifiable, Hashable, CostItem {
    let id: String
    let trip_id: String
    var city_stop_id: String?
    var category: String
    var description: String
    var on_date: String?
    var amount: Double
    var units: Double
    var currency: String
    var fx_to_base: Double
    var status: String
    var paid_amount: Double?
    var booking_ref: String?
    var notes: String?
    var scope: String
    var participant_ids: [String]?
    var approval: String
    var paid_by: String?
    var booking_url: String?
    var booking_opens: String?
}

struct AttachmentOut: Codable, Identifiable, Hashable {
    let id: String
    let trip_id: String
    let item_type: String
    let item_id: String
    let filename: String
    let content_type: String
    let created_at: String

    var icon: String {
        if content_type.hasPrefix("image/") { return "photo" }
        if content_type == "application/pdf" { return "doc.richtext" }
        return "doc.text"
    }
}

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let trip_id: String
    var attraction_id: String?
    let filename: String
    let content_type: String
    let lat: Double?
    let lon: Double?
    let taken_at: String?
}

struct CategoryBudget: Codable, Identifiable, Hashable {
    var id: String { category }
    let category: String
    let planned_base: Double
    let paid_base: Double
    let count: Int
}

/// Personal figures are private — the server fills them only for you.
struct MemberBudget: Codable, Identifiable, Hashable {
    var id: String { user.id }
    let user: UserOut
    let role: String
    let personal_budget: Double?
    let personal_base: Double?
    let personal_paid_base: Double?
}

struct BudgetSummary: Codable, Hashable {
    let base_currency: String
    let budget_enabled: Bool
    let budget_total: Double
    let committed_base: Double
    let paid_base: Double
    let remaining_vs_committed: Double
    let remaining_vs_paid: Double
    let categories: [CategoryBudget]
    let members: [MemberBudget]
    let pending_count: Int
}

// ---- helpers ----

enum Fmt {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func shortDate(_ s: String?) -> String {
        guard let s, let d = day.date(from: s) else { return s ?? "" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    static func money(_ v: Double, _ currency: String) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return "\(n.string(from: v as NSNumber) ?? "\(v)") \(currency)"
    }
}
