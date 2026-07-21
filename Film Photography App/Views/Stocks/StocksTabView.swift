import SwiftUI

struct StocksTabView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var selectedBrand = FilmStock.allBrandsLabel
    @State private var selectedFilmType = FilmStockType.allTypesLabel
    @State private var selectedStockId: UUID?

    var body: some View {
        NavigationStack {
            StocksLibraryContent(
                searchText: $searchText,
                selectedBrand: $selectedBrand,
                selectedFilmType: $selectedFilmType,
                selectedStockId: $selectedStockId
            )
            .instrumentScreen()
            .instrumentTabNavigation(title: "Library")
            .searchable(text: $searchText, prompt: "Search")
            .navigationDestination(item: $selectedStockId) { stockId in
                StockDetailView(stockId: stockId)
            }
        }
    }
}

private struct StocksLibraryContent: View {
    @Environment(AppStore.self) private var store

    @Binding var searchText: String
    @Binding var selectedBrand: String
    @Binding var selectedFilmType: String
    @Binding var selectedStockId: UUID?

    private var allBrandFilters: [String] {
        FilmStock.brandsByCount(in: store.stocks)
    }

    private var allFilmTypeFilters: [String] {
        FilmStockType.allCases.map(\.label)
    }

    /// Brands that have at least one stock matching the current type filter.
    private var brandFilters: [String] {
        guard selectedFilmType != FilmStockType.allTypesLabel else { return allBrandFilters }
        let available = Set(
            store.stocks
                .filter { $0.filmType.label == selectedFilmType }
                .map(\.brand)
        )
        return allBrandFilters.filter { available.contains($0) }
    }

    /// Types that have at least one stock matching the current brand filter.
    private var filmTypeFilters: [String] {
        guard selectedBrand != FilmStock.allBrandsLabel else { return allFilmTypeFilters }
        let available = Set(
            store.stocks
                .filter { $0.brand == selectedBrand }
                .map(\.filmType.label)
        )
        return allFilmTypeFilters.filter { available.contains($0) }
    }

    private var chipAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    FilterChipRow(
                        options: brandFilters,
                        selection: $selectedBrand,
                        clearValue: FilmStock.allBrandsLabel,
                        tintForOption: FilmStock.brandFilterTint(for:)
                    )
                    FilterChipRow(
                        options: filmTypeFilters,
                        selection: $selectedFilmType,
                        clearValue: FilmStockType.allTypesLabel
                    )
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, -4)
                .padding(.bottom, 16)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.md, alignment: .top),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.md, alignment: .top),
                ], spacing: AppTheme.Spacing.lg) {
                    ForEach(filteredStocks) { stock in
                        StockPlateRow(stock: stock)
                            .onTapGesture { selectedStockId = stock.id }
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
            .padding(.bottom, 32)
        }
        .onChange(of: selectedBrand) { _, _ in
            if selectedFilmType != FilmStockType.allTypesLabel,
               !filmTypeFilters.contains(selectedFilmType) {
                withAnimation(chipAnimation) {
                    selectedFilmType = FilmStockType.allTypesLabel
                }
            }
        }
        .onChange(of: selectedFilmType) { _, _ in
            if selectedBrand != FilmStock.allBrandsLabel,
               !brandFilters.contains(selectedBrand) {
                withAnimation(chipAnimation) {
                    selectedBrand = FilmStock.allBrandsLabel
                }
            }
        }
    }

    private var filteredStocks: [FilmStock] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.stocks.filter { stock in
            let matchesSearch = query.isEmpty ||
                stock.name.localizedCaseInsensitiveContains(query)
            let matchesBrand = selectedBrand == FilmStock.allBrandsLabel || stock.brand == selectedBrand
            let matchesType = selectedFilmType == FilmStockType.allTypesLabel
                || stock.filmType.label == selectedFilmType
            return matchesSearch && matchesBrand && matchesType
        }
    }
}

private struct StockPlateRow: View {
    @Environment(AppStore.self) private var store
    let stock: FilmStock

    private var rollsShot: Int {
        store.shotRollCount(for: stock.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            StockPlate(stock: stock)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .frame(height: 34, alignment: .topLeading)

                Text(stock.filmType.label)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(rollsShotLabel)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rollsShotLabel: String {
        rollsShot == 1 ? "1 roll shot" : "\(rollsShot) rolls shot"
    }
}

struct StockDetailView: View {
    @Environment(AppStore.self) private var store
    let stockId: UUID

    private var stock: FilmStock? {
        store.stock(for: stockId)
    }

    private var historyRolls: [Roll] {
        guard let stock else { return [] }
        return store.rollsForStock(stock.id).sorted {
            ($0.historyDate ?? .distantPast) > ($1.historyDate ?? .distantPast)
        }
    }

    private var sectionDivider: some View {
        SectionRule()
            .padding(.bottom, AppTheme.Spacing.md)
    }

    var body: some View {
        Group {
            if let stock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailHeroBlock {
                            StockPlate(stock: stock, square: false, height: 220)
                        }

                        specificationsSection(stock)
                        if !historyRolls.isEmpty {
                            sectionDivider
                            historySection
                        }
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Stock not found")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
        .instrumentDetailChrome()
        .instrumentDetailNavigation(title: stock?.name ?? "Stock")
    }

    private func specificationsSection(_ stock: FilmStock) -> some View {
        DetailSection(title: "Technical Specifications") {
            VStack(spacing: 0) {
                DataRow(label: "Manufacturer", value: stock.manufacturer, showsDivider: false)
                DataRow(label: "Type", value: stock.filmType.label)
                DataRow(label: "Process", value: stock.process.label)
                DataRow(label: "Box speed", value: "ISO \(stock.iso)")
                DataRow(label: "Usable range", value: "ISO \(stock.usableRange)")
                DataRow(label: "Push / pull", value: stock.pushPullTolerance, valueBright: false)
                DataRow(label: "Status", value: stock.productionStatus.label)
                DataRow(label: "Formats", value: stock.formatsSummary, valueBright: false)
                DataRow(label: "Grain", value: stock.grainSummary)
                DataRow(label: "Years active", value: stock.yearsActive)
                if !stock.bestFor.isEmpty {
                    DataRow(label: "Best for", value: stock.bestForSummary, valueBright: false)
                }
                DataRow(label: "Price tier", value: stock.priceTier.label)
            }
        }
    }

    private var historySection: some View {
        DetailSection(title: "History") {
            VStack(spacing: 0) {
                ForEach(Array(historyRolls.enumerated()), id: \.element.id) { index, roll in
                    DataRow(
                        label: roll.shortId,
                        value: roll.historySummary,
                        valueBright: roll.status == .inCamera || roll.status == .scanned,
                        showsDivider: index > 0
                    )
                }
            }
        }
    }
}

#Preview {
    StocksTabView()
        .environment(AppStore())
}
