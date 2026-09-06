import SwiftUI

struct AddLensView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cameraId: UUID
    var existing: CameraLens? = nil

    @State private var name = ""
    @State private var focalLength = ""
    @State private var maxAperture = ""
    @State private var notes = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, focal, aperture, notes
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HairlineRule()
                    HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                        Text("Name")
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textSecondary)
                        TextField(placeholder: "Name", text: $name, axis: .vertical)
                            .font(AppType.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .focused($focusedField, equals: .name)
                    }
                    HairlineRule()
                    fieldRow("Focal length") {
                        TextField(placeholder: "50mm", text: $focalLength)
                            .focused($focusedField, equals: .focal)
                    }
                    HairlineRule()
                    fieldRow("Maximum aperture") {
                        TextField(placeholder: "f/2", text: $maxAperture)
                            .focused($focusedField, equals: .aperture)
                    }
                    HairlineRule()
                    SectionLabel(title: "Notes", style: .detail)
                    TextField(placeholder: "Add a note", text: $notes, axis: .vertical)
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2...8)
                        .submitLabel(.return)
                        .focused($focusedField, equals: .notes)
                }
                .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle(isEditing ? "Edit Lens" : "Add Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    InstrumentCloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
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
            .onAppear {
                guard let existing else { return }
                name = existing.name
                focalLength = existing.focalLength
                maxAperture = existing.maxAperture
                notes = existing.notes
            }
        }
        .instrumentSheetChrome()
    }

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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var existing {
            existing.name = trimmed
            existing.focalLength = focalLength.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.maxAperture = maxAperture.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            store.updateLens(existing, on: cameraId)
        } else {
            store.addLens(
                to: cameraId,
                name: trimmed,
                focalLength: focalLength,
                maxAperture: maxAperture,
                notes: notes
            )
        }
        dismiss()
    }
}
