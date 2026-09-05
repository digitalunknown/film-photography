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
    @State private var alert: ExportAlert?

    private struct ExportAlert: Identifiable {
        let id = UUID()
        let title: String
        var detail: String?
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
            case .pill(let title):
                PillButtonLabel(title: isSaving ? "Saving…" : title, icon: .imageDown)
            }
        }
        .disabled(isSaving)
        .accessibilityLabel(label)
        .alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
            presenting: alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            if let detail = alert.detail {
                Text(detail)
            }
        }
    }

    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await PhotoLibraryExport.save(scans)
            alert = ExportAlert(
                title: scans.count == 1
                    ? "Saved to Photos"
                    : "\(scans.count) scans saved to Photos"
            )
        } catch {
            alert = ExportAlert(title: "Couldn't save", detail: error.localizedDescription)
        }
    }
}
