import SwiftUI

struct StatusBadge: View {
    let count: Int
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(badgeColor)
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.15))
        )
    }

    private var badgeColor: Color {
        switch status {
        case .active: .green
        case .recentlyIdle: .yellow
        case .archived: .gray
        }
    }
}
