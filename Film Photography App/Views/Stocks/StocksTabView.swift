import SwiftUI

struct StocksTabView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var selectedCategory: StockCategory = .all
    @State private var selectedStockId: UUID?

    private var filterOptions: [String] {
        StockCategory.allCases.map(\.rawValue)
    }

    private var filterSelection: Binding<String> {
        Binding(
            get: { selectedCategory.rawValue },
            set: { value in
                selectedCategory = StockCategory.allCases.first { $0.rawValue == value } ?? .all
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FilterTextRow(options: filterOptions, selection: filterSelection)
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.bottom, 24)

                    HairlineRule()
                        .padding(.horizontal, AppTheme.horizontalPadding)
                        .padding(.bottom, 24)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 28) {
                        ForEach(filteredStocks) { stock in
                            StockPlateRow(stock: stock)
                                .onTapGesture { selectedStockId = stock.id }
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                }
                .padding(.bottom, 32)
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "Stocks")
            .searchable(text: $searchText, prompt: "Search stocks")
            .navigationDestination(item: $selectedStockId) { stockId in
                StockDetailView(stockId: stockId)
            }
        }
    }

    private var filteredStocks: [FilmStock] {
        store.stocks.filter { stock in
            let matchesSearch = searchText.isEmpty ||
                stock.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory: Bool = {
                switch selectedCategory {
                case .all: return true
                case .colorNeg: return stock.category == .colorNeg
                case .blackAndWhite: return stock.category == .blackAndWhite
                case .slide: return stock.category == .slide
                }
            }()
            return matchesSearch && matchesCategory
        }
    }
}

private struct StockPlateRow: View {
    @Environment(AppStore.self) private var store
    let stock: FilmStock

    private var rollsShot: Int {
        store.shotRollCount(for: stock.id)
    }

    private var fridgeCount: Int {
        store.fridgeCount(for: stock.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StockPlate(stock: stock)

            Text(stock.name)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Text(stock.processISOText)
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)

            HStack {
                Text(fridgeCount > 0 ? "In fridge" : "0 in fridge")
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(fridgeCount > 0 ? "\(fridgeCount)" : "·")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            HStack {
                Text("Rolls shot")
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("\(rollsShot)")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .opacity(rollsShot > 0 ? 1 : 0)
            .frame(height: rollsShot > 0 ? nil : 0)
            .clipped()
        }
    }
}

private struct MonthUsage: Identifiable {
    let id: String
    let label: String
    let count: Int
}

struct StockDetailView: View {
    @Environment(AppStore.self) private var store
    let stockId: UUID

    private var stock: FilmStock? {
        store.stock(for: stockId)
    }

    private var stockRolls: [Roll] {
        guard let stock else { return [] }
        return store.rollsForStock(stock.id)
    }

    private var rollsShot: Int {
        guard let stock else { return 0 }
        return store.shotRollCount(for: stock.id)
    }

    private var fridgeCount: Int {
        guard let stock else { return 0 }
        return store.fridgeCount(for: stock.id)
    }

    private var historyRolls: [Roll] {
        stockRolls.sorted {
            ($0.historyDate ?? .distantPast) > ($1.historyDate ?? .distantPast)
        }
    }

    private var monthlyUsage: [MonthUsage] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        let shotRolls = stockRolls.filter { $0.status.countsAsShot }
        let now = Date()

        return (0..<6).reversed().compactMap { offset -> MonthUsage? in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let label = formatter.string(from: month)
            let count = shotRolls.filter { roll in
                guard let date = roll.finishedDate ?? roll.loadedDate else { return false }
                return calendar.isDate(date, equalTo: month, toGranularity: .month)
            }.count
            return MonthUsage(id: label, label: label, count: count)
        }
    }

    private var hasUsage: Bool {
        monthlyUsage.contains { $0.count > 0 }
    }

    var body: some View {
        Group {
            if let stock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        StockPlate(stock: stock, square: false)
                            .padding(.bottom, 24)

                        HeroMetric(
                            label: "Rolls shot",
                            sublabel: fridgeCount > 0 ? "\(fridgeCount) in fridge · \(stock.processISOText)" : stock.processISOText,
                            value: "\(rollsShot)"
                        )
                        .padding(.bottom, 28)

                        HairlineRule().padding(.bottom, 28)

                        DetailSection(title: "Inventory") {
                            VStack(spacing: 10) {
                                DataRow(
                                    label: "In fridge",
                                    value: fridgeCount == 1 ? "1 roll" : "\(fridgeCount) rolls",
                                    valueBright: fridgeCount > 0
                                )
                                if fridgeCount == 0 {
                                    Text("0 in fridge · restock when empty")
                                        .font(InstrumentFont.mono(11))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                            }
                        }

                        DetailSection(title: "Usage") {
                            if hasUsage {
                                VStack(spacing: 10) {
                                    ForEach(monthlyUsage) { month in
                                        DataRow(
                                            label: month.label,
                                            value: month.count == 1 ? "1 roll" : "\(month.count) rolls",
                                            valueBright: month.count > 0
                                        )
                                    }
                                }
                            } else {
                                Text("No rolls shot in the last 6 months")
                                    .font(InstrumentFont.mono(12))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }

                        DetailSection(title: "Spec") {
                            VStack(spacing: 10) {
                                DataRow(label: "Process", value: stock.process.label)
                                DataRow(label: "ISO", value: "\(stock.iso)")
                                DataRow(label: "Status", value: stock.isDiscontinued ? "Discontinued" : "Current")
                                if !stock.notes.isEmpty {
                                    DataRow(label: "Notes", value: stock.notes, valueBright: false)
                                }
                            }
                        }

                        if !historyRolls.isEmpty {
                            DetailSection(title: "History") {
                                VStack(spacing: 10) {
                                    ForEach(historyRolls) { roll in
                                        DataRow(
                                            label: roll.shortId,
                                            value: roll.historySummary,
                                            valueBright: roll.status == .inCamera || roll.status == .scanned
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
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
}

#Preview {
    StocksTabView()
        .environment(AppStore())
}
