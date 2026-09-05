import SwiftUI

/// Searchable grid of film stocks for picking a roll from the catalog.
struct StockPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let title: String
    let selectedStockId: UUID?
    let onSelect: (FilmStock) -> Void

    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
    ]

    private var filteredStocks: [FilmStock] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.stocks }
        return store.stocks.filter { stock in
            stock.name.localizedCaseInsensitiveContains(query)
                || stock.brand.localizedCaseInsensitiveContains(query)
                || stock.shortCode.localizedCaseInsensitiveContains(query)
                || "\(stock.iso)".contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if filteredStocks.isEmpty {
                    Text(searchText.isEmpty ? "No stocks in library." : "No matches.")
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppTheme.Spacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: AppTheme.Spacing.lg) {
                        ForEach(filteredStocks) { stock in
                            Button {
                                onSelect(stock)
                                dismiss()
                            } label: {
                                stockCell(stock)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.xl)
                }
            }
            .instrumentScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppType.body)
                }
            }
        }
        .instrumentSheetChrome()
    }

    private func stockCell(_ stock: FilmStock) -> some View {
        let isSelected = stock.id == selectedStockId
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            StockPlate(stock: stock)
                .overlay {
                    Rectangle()
                        .strokeBorder(
                            isSelected ? AppTheme.textPrimary : Color.clear,
                            lineWidth: 1.5
                        )
                }

            Text(stock.name)
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 28, alignment: .top)
        }
        .accessibilityLabel(stock.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    StockPickerSheet(title: "Choose Film", selectedStockId: nil) { _ in }
        .environment(AppStore())
}
