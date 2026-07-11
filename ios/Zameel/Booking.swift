import SwiftUI
import UserNotifications

/// Where to book + when sales open. Many tickets (USJ, teamLab, popular
/// restaurants) only go on sale 60-90 days before the date — the reminder is
/// a local notification on this device the morning sales open.
struct BookingInfoSection: View {
    let title: String
    let item: any CostItem
    @State private var reminderState: ReminderState = .unknown

    enum ReminderState { case unknown, none, scheduled, denied }

    private var opensDate: Date? {
        item.booking_opens.flatMap { Fmt.day.date(from: $0) }
    }

    var body: some View {
        if item.booking_url != nil || item.booking_opens != nil {
            Section("Booking") {
                if let opens = item.booking_opens, let date = opensDate {
                    HStack {
                        IconChip(system: "calendar.badge.clock", color: .pink, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(date > Date.now ? "Sales open \(Fmt.shortDate(opens)), \(year(date))"
                                                 : "Sales are open — book now!")
                                .font(.subheadline.weight(.medium))
                            if date > Date.now {
                                Text(countdown(to: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let urlString = item.booking_url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack {
                            IconChip(system: "safari", color: .blue, size: 30)
                            Text("Book at \(url.host() ?? urlString)")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let date = opensDate, date > Date.now {
                    switch reminderState {
                    case .scheduled:
                        Label("Reminder set for that morning", systemImage: "bell.badge.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    case .denied:
                        Label("Notifications are off — enable them in Settings", systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    default:
                        Button {
                            remind(on: date)
                        } label: {
                            Label("Remind me when booking opens", systemImage: "bell")
                        }
                    }
                }
            }
            .task { await checkExisting() }
        }
    }

    private func year(_ d: Date) -> String {
        d.formatted(.dateTime.year())
    }

    private func countdown(to date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        return "in \(days) day\(days == 1 ? "" : "s")"
    }

    private var reminderID: String { "booking-\(item.booking_opens ?? "")-\(title)" }

    private func checkExisting() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == reminderID }) {
            reminderState = .scheduled
        } else {
            reminderState = .none
        }
    }

    private func remind(on date: Date) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                reminderState = .denied
                return
            }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = "Booking opens today 🎟️"
            content.body = title
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: reminderID, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
            reminderState = .scheduled
        }
    }
}

/// Editable booking fields for the edit forms.
struct BookingFieldsSection: View {
    @Binding var cost: CostFields

    var body: some View {
        Section("Booking") {
            TextField("Booking URL", text: $cost.bookingUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Sales open on a specific date", isOn: $cost.hasBookingOpens)
            if cost.hasBookingOpens {
                DatePicker("Sales open", selection: $cost.bookingOpens, displayedComponents: .date)
            }
        }
    }
}
