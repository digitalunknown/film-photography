import SwiftUI

struct AddCameraView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lensSubtitle = ""
    @State private var cameraType = "Rangefinder"
    @State private var serialNumber = ""
    @State private var purchaseDate = Date()
    @State private var includePurchaseDate = false
    @State private var purchasePrice = ""
    @State private var quirkNote = ""

    private let cameraTypes = ["Rangefinder", "SLR", "Point & shoot", "TLR", "Large format", "Instant"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lensSubtitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Body") {
                    TextField("Name", text: $name, prompt: Text("Konica C35 FD"))
                    TextField("Lens", text: $lensSubtitle, prompt: Text("38mm f/1.8"))
                    Picker("Type", selection: $cameraType) {
                        ForEach(cameraTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }

                Section("Collection details") {
                    TextField("Serial number", text: $serialNumber)
                    Toggle("Purchase date", isOn: $includePurchaseDate)
                    if includePurchaseDate {
                        DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
                    }
                    TextField("Purchase price", text: $purchasePrice)
                        .keyboardType(.decimalPad)
                }

                Section("Quirks") {
                    TextField("Notes", text: $quirkNote, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Add Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(InstrumentFont.mono(13))
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        store.addCamera(
            name: name.trimmingCharacters(in: .whitespaces),
            lensSubtitle: lensSubtitle.trimmingCharacters(in: .whitespaces),
            cameraType: cameraType,
            serialNumber: serialNumber,
            purchaseDate: includePurchaseDate ? purchaseDate : nil,
            purchasePrice: Double(purchasePrice),
            quirkNote: quirkNote
        )
        dismiss()
    }
}

#Preview {
    AddCameraView()
        .environment(AppStore())
}
