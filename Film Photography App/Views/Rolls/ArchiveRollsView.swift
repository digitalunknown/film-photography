import SwiftUI

struct ArchiveRollsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.archivedRolls.enumerated()), id: \.element.id) { index, roll in
                    NavigationLink(value: roll) {
                        ArchiveRollRow(roll: roll)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.vertical, AppTheme.rowSpacing)

                    if index < store.archivedRolls.count - 1 {
                        HairlineRule()
                            .padding(.horizontal, AppTheme.horizontalPadding)
                    }
                }
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .instrumentScreen()
        .instrumentDetailNavigation(title: "Archive")
    }
}

private struct ArchiveRollRow: View {
    @Environment(AppStore.self) private var store
    let roll: Roll

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
            RollPlate(stock: store.stock(for: roll.stockId), size: 64)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(store.label(for: roll))
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(subtitle)
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if let date = roll.archivedDate ?? roll.scannedDate {
                Text(DateFormatters.short.string(from: date))
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    /// The camera it was shot on, or failing that what the roll itself was.
    private var subtitle: String {
        if let camera = store.camera(for: roll.cameraId) {
            return camera.name
        }
        return "\(roll.format.displayName) · \(roll.totalExposures) exp"
    }
}

#Preview {
    NavigationStack {
        ArchiveRollsView()
    }
    .environment(AppStore())
}
