import SwiftUI

struct AddCameraView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lensSubtitle = ""
    @State private var cameraType = "Rangefinder"
    @State private var serialNumber = ""
    @State private var purchaseDate: Date?
    @State private var purchaseDateDraft = Date()
    @State private var showingPurchaseDatePicker = false
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    formRows
                }
                .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle("Add Camera")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPurchaseDatePicker) {
                purchaseDatePickerSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    InstrumentCloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(AppType.body)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    InstrumentKeyboardDoneButton {
                        focusedField = nil
                    }
                }
            }
        }
        .instrumentSheetChrome()
    }

    /// One 16pt stack of label/value rows with explicit rules — no section headings, and
    /// every value pinned to the trailing edge, matching the camera detail table.
    @ViewBuilder
    private var formRows: some View {
        HairlineRule()
        fieldRow("Name") {
            TextField(placeholder: "Name", text: $name)
                .focused($focusedField, equals: .name)
        }
        HairlineRule()
        fieldRow("Lens") {
            TextField(placeholder: "Lens", text: $lensSubtitle)
                .focused($focusedField, equals: .lens)
        }
        HairlineRule()
        menuRow("Type", value: cameraType) {
            ForEach(cameraTypes, id: \.self) { type in
                Button(type) { cameraType = type }
            }
        }
        HairlineRule()
        fieldRow("Serial number") {
            TextField(placeholder: "Optional", text: $serialNumber)
                .focused($focusedField, equals: .serial)
        }
        HairlineRule()
        purchaseDateRow
        HairlineRule()
        fieldRow("Purchase price") {
            TextField(placeholder: "Optional", text: $purchasePrice)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .price)
        }
        HairlineRule()
        SectionLabel(title: "Notes", style: .detail)
        TextField(placeholder: "Add a note", text: $quirkNote, axis: .vertical)
            .font(AppType.body)
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(2...8)
            .submitLabel(.return)
            .focused($focusedField, equals: .quirks)
    }

    private var purchaseDateRow: some View {
        Button {
            purchaseDateDraft = purchaseDate ?? Date()
            focusedField = nil
            showingPurchaseDatePicker = true
        } label: {
            DetailFieldRow(label: "Purchase date") {
                DetailFieldValue(text: purchaseDateDisplay)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var purchaseDateDisplay: String {
        guard let purchaseDate else { return "Not set" }
        return DateFormatters.medium.string(from: purchaseDate)
    }

    private var purchaseDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                DatePicker(
                    "Purchase date",
                    selection: $purchaseDateDraft,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.horizontalPadding)

                Spacer(minLength: 0)
            }
            .instrumentScreen()
            .navigationTitle("Purchase date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        purchaseDate = nil
                        showingPurchaseDatePicker = false
                    }
                    .font(AppType.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        purchaseDate = Calendar.current.startOfDay(for: purchaseDateDraft)
                        showingPurchaseDatePicker = false
                    }
                    .font(AppType.body)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Row builders

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

    /// Editable variant — the field right-aligns into the value column.
    private func fieldRow<Content: View>(
        _ label: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DetailFieldRow(label: label) {
            content()
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        store.addCamera(
            name: name.trimmingCharacters(in: .whitespaces),
            lensSubtitle: lensSubtitle.trimmingCharacters(in: .whitespaces),
            cameraType: cameraType,
            serialNumber: serialNumber,
            purchaseDate: purchaseDate,
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
