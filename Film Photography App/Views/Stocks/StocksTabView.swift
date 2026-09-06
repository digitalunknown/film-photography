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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.showingSettings = true
                    } label: {
                        LucideIcon(.fileText)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .navigationDestination(item: $selectedStockId) { stockId in
                StockDetailView(stockId: stockId)
            }
        }
    }
}

private struct StocksLibraryContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.isSearching) private var isSearching

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
                if !isSearching {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.lg, alignment: .top),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.lg, alignment: .top),
                ], spacing: AppTheme.Spacing.xl) {
                    ForEach(filteredStocks) { stock in
                        StockPlateRow(stock: stock)
                            .onTapGesture { selectedStockId = stock.id }
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
            .padding(.bottom, AppTheme.Spacing.xl)
            .animation(chipAnimation, value: isSearching)
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
            let matchesSearch = stock.matchesSearch(query)
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

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                    Text(stock.name)
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if stock.isDiscontinued {
                        DiscontinuedLabel(style: .compact)
                            .layoutPriority(1)
                    }
                }
                .frame(height: 34, alignment: .topLeading)

                if let alsoSoldAs = stock.alsoSoldAsLine {
                    Text(alsoSoldAs)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Text(stock.filmType.label)
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(rollsShotLabel)
                    .font(AppType.callout)
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

    var body: some View {
        Group {
            if let stock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailHeroBlock {
                            if stock.rollImageName != nil {
                                RollCanister3D(stock: stock)
                                    .frame(width: 250, height: 250)
                                    .frame(maxWidth: .infinity)
                            } else {
                                StockPlate(stock: stock)
                                    .frame(width: 250, height: 250)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if !stock.libraryDescription.isEmpty {
                            descriptionBlock(stock.libraryDescription)
                        }

                        specRows(stock)
                        if !historyRolls.isEmpty {
                            historySection
                        }
                    }
                    .instrumentDetailContent()
                }
                .instrumentDetailScroll()
            } else {
                VStack(alignment: .leading) {
                    Text("Stock not found")
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
        .instrumentDetailChrome()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(stock?.name ?? "Stock")
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if stock?.isDiscontinued == true {
                        DiscontinuedLabel()
                    }
                }
            }
        }
    }

    private func descriptionBlock(_ text: String) -> some View {
        Text(text)
            .font(AppType.body)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Same unlabeled table as roll detail: rule, label left, value trailing.
    @ViewBuilder
    private func specRows(_ stock: FilmStock) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HairlineRule()
            valueRow("Manufacturer", stock.manufacturer)
            if let alsoSoldAs = stock.alsoSoldAs {
                HairlineRule()
                valueRow("Also sold as", alsoSoldAs)
            }
            HairlineRule()
            valueRow("Type", stock.filmType.label)
            HairlineRule()
            valueRow("Process", stock.process.label)
            HairlineRule()
            valueRow("Box speed", "ISO/ASA \(stock.iso)")
            if !stock.usableRange.isEmpty {
                HairlineRule()
                valueRow("Usable range", stock.usableRangeDisplay)
            }
            if !stock.pushPullTolerance.isEmpty {
                HairlineRule()
                valueRow("Push / pull", stock.pushPullTolerance)
            }
            HairlineRule()
            valueRow("Status", stock.productionStatus.label)
            if !stock.formatsSummary.isEmpty {
                HairlineRule()
                valueRow("Formats", stock.formatsSummary)
            }
            HairlineRule()
            valueRow("Grain", stock.grainSummary)
            if !stock.yearsActive.isEmpty {
                HairlineRule()
                valueRow("Years active", stock.yearsActive)
            }
            if !stock.bestFor.isEmpty {
                HairlineRule()
                valueRow("Best for", stock.bestForSummary)
            }
            HairlineRule()
            valueRow("Price tier", stock.priceTier.label)
        }
        .padding(.top, AppTheme.tableGap)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        DetailFieldRow(label: label) {
            DetailFieldValue(text: value)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HairlineRule()
            SectionLabel(title: "History", style: .detail)
            VStack(spacing: 0) {
                ForEach(Array(historyRolls.enumerated()), id: \.element.id) { index, roll in
                    InstrumentRow(
                        label: historyDateText(for: roll),
                        showsDivider: index > 0
                    ) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            let cameraName = store.camera(for: roll.cameraId)?.name
                            Text(cameraName ?? "Not Set")
                                .font(AppType.body)
                                .foregroundStyle(cameraName == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(roll.status.displayName)
                                .font(AppType.body)
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private func historyDateText(for roll: Roll) -> String {
        guard let date = roll.historyDate else { return "—" }
        return DateFormatters.medium.string(from: date)
    }
}

#Preview {
    StocksTabView()
        .environment(AppStore())
}
