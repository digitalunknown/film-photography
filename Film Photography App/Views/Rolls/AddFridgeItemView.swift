import SwiftUI

struct AddFridgeItemView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStockId: UUID?
    @State private var showingStockPicker = false
    @State private var format: FilmFormat = .format35Full
    @State private var quantity = 1
    @State private var includeExpiryDate = false
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    private var selectedStock: FilmStock? {
        selectedStockId.flatMap { store.stock(for: $0) }
    }

    private var sectionDivider: some View {
        HairlineRule()
            .padding(.bottom, AppTheme.Spacing.lg)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection(title: "Stock") {
                        VStack(spacing: 0) {
                            Button {
                                showingStockPicker = true
                            } label: {
                                InstrumentRow(label: "Film", showsDivider: false) {
                                    HStack(spacing: AppTheme.Spacing.sm) {
                                        Text(selectedStock?.name ?? "Choose film")
                                            .font(AppType.body)
                                            .foregroundStyle(
                                                selectedStock == nil
                                                    ? AppTheme.textSecondary
                                                    : AppTheme.textPrimary
                                            )
                                        Spacer(minLength: 0)
                                        LucideIcon(.chevronsUpDown)
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            InstrumentMenuRow(
                                label: "Format",
                                value: format.displayName,
                                valueBright: true
                            ) {
                                ForEach(FilmFormat.allCases) { fmt in
                                    Button(fmt.displayName) { format = fmt }
                                }
                            }

                            InstrumentRow(label: "Quantity") {
                                HStack(spacing: AppTheme.Spacing.lg) {
                                    Button {
                                        quantity = max(quantity - 1, 1)
                                    } label: {
                                        Text("−")
                                            .font(AppType.title)
                                            .foregroundStyle(quantity > 1 ? AppTheme.textPrimary : AppTheme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(quantity <= 1)

                                    Text("\(quantity)")
                                        .font(AppType.body)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .monospacedDigit()

                                    Button {
                                        quantity = min(quantity + 1, 99)
                                    } label: {
                                        Text("+")
                                            .font(AppType.title)
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer(minLength: 0)
                                }
                            }

                            InstrumentRow(label: "Expiration date") {
                                Toggle("", isOn: $includeExpiryDate)
                                    .labelsHidden()
                                    .tint(AppTheme.textPrimary)
                            }

                            if includeExpiryDate {
                                MonthYearPicker(date: $expiryDate)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 120)
                                    .padding(.top, AppTheme.Spacing.sm)
                            }
                        }
                    }
                }
                .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle("Add to Fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(AppType.body)
                        .disabled(selectedStockId == nil)
                }
            }
            .sheet(isPresented: $showingStockPicker) {
                StockPickerSheet(
                    title: "Choose Film",
                    selectedStockId: selectedStockId
                ) { stock in
                    selectedStockId = stock.id
                }
            }
            .onAppear {
                if selectedStockId == nil {
                    selectedStockId = store.stocks.first?.id
                }
            }
        }
        .instrumentSheetChrome()
    }

    private func save() {
        guard let stockId = selectedStockId else { return }
        store.addFridgeItem(
            stockId: stockId,
            format: format,
            quantity: quantity,
            expiryDate: includeExpiryDate ? ExpirationDate.normalize(expiryDate) : nil
        )
        dismiss()
    }
}

#Preview {
    AddFridgeItemView()
        .environment(AppStore())
}
