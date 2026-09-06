import SwiftUI

/// Sends scans out of the app with everything logged for them written in.
///
/// Saving to Photos leads, since a finished scan usually belongs back in the library
/// beside the digital shots. Sharing hands the file itself to anything else.
struct ExportScansButton: View {
    let scans: [ExportedScan]
    var label: String
    var style: Style = .icon

    /// A bare icon for a toolbar, or an outlined pill for sitting beside the other roll
    /// actions under the strip.
    enum Style {
        case icon
        case pill(title: String)
    }

    @State private var isSaving = false
    @State private var statusTitle: String?

    private var pillTitle: String {
        if let statusTitle { return statusTitle }
        if isSaving { return "Saving…" }
        if case .pill(let title) = style { return title }
        return "Save"
    }

    var body: some View {
        Menu {
            Button("Save to Photos", lucide: .imageDown) {
                Task { await saveToPhotos() }
            }
            ShareLink(items: scans) { scan in
                SharePreview(scan.exportName)
            } label: {
                Label("Share…", lucide: .share)
            }
        } label: {
            switch style {
            case .icon:
                LucideIcon(.imageDown)
                    .foregroundStyle(AppTheme.textPrimary)
            case .pill:
                PillButtonLabel(title: pillTitle, icon: .imageDown)
            }
        }
        .disabled(isSaving)
        .accessibilityLabel(label)
        .accessibilityValue(statusTitle ?? "")
    }

    private func saveToPhotos() async {
        isSaving = true
        statusTitle = nil
        defer { isSaving = false }

        do {
            try await PhotoLibraryExport.save(scans)
            statusTitle = scans.count == 1 ? "Saved" : "Saved \(scans.count)"
        } catch {
            statusTitle = "Couldn't save"
        }

        try? await Task.sleep(for: .seconds(2))
        statusTitle = nil
    }
}
