import SwiftUI

struct AddFridgeItemView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStockId: UUID?
    @State private var format: FilmFormat = .format35Full
    @State private var quantity = 1
    @State private var includeExpiryDate = false
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Stock") {
                    Picker("Film", selection: $selectedStockId) {
                        Text("Select stock").tag(nil as UUID?)
                        ForEach(store.stocks) { stock in
                            Text(stock.name).tag(stock.id as UUID?)
                        }
                    }

                    Picker("Format", selection: $format) {
                        ForEach(FilmFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }

                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)

                    Toggle("Expiry date", isOn: $includeExpiryDate)
                    if includeExpiryDate {
                        DatePicker("Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Add to Fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(InstrumentFont.mono(13))
                        .disabled(selectedStockId == nil)
                }
            }
            .onAppear {
                if selectedStockId == nil {
                    selectedStockId = store.stocks.first?.id
                }
            }
        }
    }

    private func save() {
        guard let stockId = selectedStockId else { return }
        store.addFridgeItem(
            stockId: stockId,
            format: format,
            quantity: quantity,
            expiryDate: includeExpiryDate ? expiryDate : nil
        )
        dismiss()
    }
}

#Preview {
    AddFridgeItemView()
        .environment(AppStore())
}
