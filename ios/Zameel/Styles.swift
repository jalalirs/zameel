import SwiftUI

/// One place for the app's look: gradient accents, chips, avatars.
enum Style {
    static let hero = LinearGradient(
        colors: [Color(red: 0.25, green: 0.32, blue: 0.9), Color(red: 0.45, green: 0.25, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let subtle = LinearGradient(
        colors: [Color.indigo.opacity(0.14), Color.purple.opacity(0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func categoryColor(_ c: String) -> Color {
        switch c {
        case "travel": .blue
        case "hotels": .purple
        case "attractions": .pink
        case "transport": .teal
        default: .orange
        }
    }
}

/// Small tinted circle with an SF Symbol — used as a leading icon everywhere.
struct IconChip: View {
    let system: String
    var color: Color = .indigo
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: system)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
    }
}

/// Initials avatar for a user.
struct Avatar: View {
    let name: String
    var size: CGFloat = 32
    var inverted = false

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(inverted ? Color.indigo : .white)
            .frame(width: size, height: size)
            .background(inverted ? AnyShapeStyle(.white) : AnyShapeStyle(Style.hero), in: Circle())
    }
}

/// Overlapping row of member avatars.
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(5).enumerated()), id: \.offset) { _, name in
                Avatar(name: name, size: size, inverted: true)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))
            }
            if names.count > 5 {
                Text("+\(names.count - 5)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.25), in: Circle())
            }
        }
    }
}

struct ApprovalBadge: View {
    let approval: String

    var body: some View {
        if approval == "pending" {
            Label("pending", systemImage: "clock")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        } else if approval == "rejected" {
            Label("kept personal", systemImage: "hand.raised")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
    }
}
