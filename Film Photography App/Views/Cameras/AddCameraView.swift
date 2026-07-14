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
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, lens, serial, price, quirks
    }

    private let cameraTypes = ["Rangefinder", "SLR", "Point & shoot", "TLR", "Large format", "Instant"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lensSubtitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sectionDivider: some View {
        SectionRule()
            .padding(.bottom, AppTheme.Spacing.md)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection(title: "Body") {
                        VStack(spacing: 0) {
                            InstrumentEditableRow(label: "Name", showsDivider: false) {
                                TextField("Konica C35 FD", text: $name)
                                    .focused($focusedField, equals: .name)
                            }
                            InstrumentEditableRow(label: "Lens") {
                                TextField("38mm f/1.8", text: $lensSubtitle)
                                    .focused($focusedField, equals: .lens)
                            }
                            InstrumentMenuRow(
                                label: "Type",
                                value: cameraType,
                                valueBright: true
                            ) {
                                ForEach(cameraTypes, id: \.self) { type in
                                    Button(type) { cameraType = type }
                                }
                            }
                        }
                    }

                    sectionDivider

                    DetailSection(title: "Collection") {
                        VStack(spacing: 0) {
                            InstrumentEditableRow(label: "Serial", showsDivider: false) {
                                TextField("Optional", text: $serialNumber)
                                    .focused($focusedField, equals: .serial)
                            }
                            InstrumentRow(label: "Purchase date") {
                                Toggle("", isOn: $includePurchaseDate)
                                    .labelsHidden()
                                    .tint(AppTheme.textPrimary)
                            }
                            if includePurchaseDate {
                                InstrumentRow(label: "Date") {
                                    DatePicker(
                                        "Date",
                                        selection: $purchaseDate,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                }
                            }
                            InstrumentEditableRow(label: "Price") {
                                TextField("Optional", text: $purchasePrice)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .price)
                            }
                        }
                    }

                    sectionDivider

                    DetailSection(title: "Notes") {
                        TextField("Quirks, servicing, tips", text: $quirkNote, axis: .vertical)
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .quirks)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }
                .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
        .instrumentSheetChrome()
    }

    private func save() {
        store.addCamera(
            name: name.trimmingCharacters(in: .whitespaces),
            lensSubtitle: lensSubtitle.trimmingCharacters(in: .whitespaces),
            cameraType: cameraType,
            serialNumber: serialNumber,
            purchaseDate: includePurchaseDate ? purchaseDate : nil,
            purchasePrice: Double(purchasePrice.replacingOccurrences(of: ",", with: ".")),
            quirkNote: quirkNote
        )
        dismiss()
    }
}

#Preview {
    AddCameraView()
        .environment(AppStore())
}
