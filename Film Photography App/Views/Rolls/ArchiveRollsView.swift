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
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            RollPlate(stock: store.stock(for: roll.stockId), size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.stock(for: roll.stockId)?.name ?? roll.shortId)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(roll.shortId)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if let date = roll.archivedDate ?? roll.scannedDate {
                Text(DateFormatters.short.string(from: date))
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ArchiveRollsView()
    }
    .environment(AppStore())
}
