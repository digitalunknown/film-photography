import SwiftUI

/// First-win add: pick a stock, how many rolls, and where they live.
struct AddInventoryFilmView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStockId: UUID?
    @State private var showingStockPicker = false
    @State private var format: FilmFormat = .format35Full
    @State private var quantity = 1
    @State private var storage = StorageMethod.roomTemperature
    @State private var includeExpiryDate = false
    @State private var expiryDate = Date()
    @State private var showingExpiryPicker = false

    private var selectedStock: FilmStock? {
        selectedStockId.flatMap { store.stock(for: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HairlineRule()
                    filmRow
                    HairlineRule()
                    menuRow("Format", value: format.displayName) {
                        ForEach(FilmFormat.allCases) { option in
                            Button(option.displayName) { format = option }
                        }
                    }
                    HairlineRule()
                    quantityRow
                    HairlineRule()
                    menuRow("Storage method", value: storage.displayName) {
                        ForEach(StorageMethod.allCases) { method in
                            Button(method.displayName) { storage = method }
                        }
                    }
                    HairlineRule()
                    expirationRow
                }
                .instrumentDetailContent()
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle("Add Film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    InstrumentCloseButton { dismiss() }
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
            .sheet(isPresented: $showingExpiryPicker) {
                expirationPickerSheet
            }
        }
        .instrumentSheetChrome()
    }

    private var filmRow: some View {
        Button {
            showingStockPicker = true
        } label: {
            DetailFieldRow(label: "Film") {
                HStack(spacing: AppTheme.Spacing.xs) {
                    DetailFieldValue(
                        text: selectedStock?.name ?? "Choose film",
                        isPlaceholder: selectedStock == nil
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: 180, alignment: .trailing)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Film")
    }

    private var quantityRow: some View {
        DetailFieldRow(label: "Quantity") {
            NumberStepper(
                canDecrement: quantity > 1,
                decrementLabel: "Fewer rolls",
                incrementLabel: "More rolls",
                onDecrement: { quantity = max(quantity - 1, 1) },
                onIncrement: { quantity = min(quantity + 1, 99) }
            ) {
                Text("\(quantity)")
            }
        }
    }

    private var expirationRow: some View {
        Button {
            showingExpiryPicker = true
        } label: {
            DetailFieldRow(label: "Expiration date") {
                DetailFieldValue(
                    text: includeExpiryDate
                        ? DateFormatters.monthYear.string(from: expiryDate)
                        : "Not set"
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expirationPickerSheet: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                MonthYearPicker(date: $expiryDate)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .instrumentScreen()
            .navigationTitle("Expiration date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        includeExpiryDate = false
                        showingExpiryPicker = false
                    }
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        includeExpiryDate = true
                        expiryDate = ExpirationDate.normalize(expiryDate)
                        showingExpiryPicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func menuRow<Content: View>(
        _ label: String,
        value: String,
        @ViewBuilder menu: @escaping () -> Content
    ) -> some View {
        DetailFieldRow(label: label) {
            Menu {
                menu()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    DetailFieldValue(text: value)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    private func save() {
        guard let stockId = selectedStockId else { return }
        store.addInventoryRolls(
            stockId: stockId,
            quantity: quantity,
            format: format,
            storage: storage,
            expiryDate: includeExpiryDate ? ExpirationDate.normalize(expiryDate) : nil
        )
        dismiss()
    }
}

#Preview {
    AddInventoryFilmView()
        .environment(AppStore())
}
