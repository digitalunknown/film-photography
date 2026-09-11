import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pendingImport: URL?
    @State private var showingReplaceConfirm = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isExporting = false
    @State private var documentPicker = BackupDocumentPicker()

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    SectionLabel(title: "Data", style: .detail)
                    DetailFieldRow(label: "iCloud Sync") {
                        Toggle("iCloud Sync", isOn: $store.iCloudSyncEnabled)
                            .labelsHidden()
                            .tint(AppTheme.textSecondary)
                    }
                    if store.iCloudSyncEnabled {
                        Text(store.iCloudStatusLine)
                            .font(AppType.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("When on, cameras, rolls, and notes are mirrored to iCloud with your Apple ID. Scan images stay on this device.")
                            .font(AppType.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    HairlineRule()

                    Text("Export a copy of your cameras, rolls, and scans. Import replaces everything on this device, then syncs to iCloud if sync is on.")
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)

                    Button {
                        Task { await exportBackup() }
                    } label: {
                        PillButtonLabel(
                            title: isExporting ? "Generating Backup" : "Export Backup",
                            icon: .share,
                            isBusy: isExporting
                        )
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isExporting)

                    Button {
                        presentImporter()
                    } label: {
                        PillButtonLabel(title: "Import Backup", icon: .fileText)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                }
                .instrumentDetailContent()
            }
            .instrumentDetailScroll()
            .instrumentScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    InstrumentCloseButton { dismiss() }
                }
            }
            .alert("Replace this library?", isPresented: $showingReplaceConfirm) {
                Button("Replace", role: .destructive) {
                    if let pendingImport { importBackup(pendingImport) }
                    pendingImport = nil
                }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("This replaces your cameras, rolls, and scans with the backup. The previous save is kept as a recovery file on this device.")
            }
            .alert("Backup", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .instrumentSheetChrome()
    }

    /// Builds the zip, then hands it to the system share sheet from UIKit. A SwiftUI
    /// share sheet or file importer on top of this detent sheet never appears and
    /// leaves the app wedged.
    private func exportBackup() async {
        isExporting = true
        defer { isExporting = false }
        await Task.yield()

        do {
            let url = try await store.exportLibraryBackup()
            SystemPresenter.share(file: url)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func presentImporter() {
        documentPicker.onPick = { url in
            pendingImport = url
            showingReplaceConfirm = true
        }
        documentPicker.onCancel = {}

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.zip, .json],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = documentPicker
        SystemPresenter.present(picker)
    }

    private func importBackup(_ url: URL) {
        do {
            try store.restoreLibrary(from: url)
            dismiss()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

/// Kept alive for the life of the settings screen so the document picker can call back.
@MainActor
private final class BackupDocumentPicker: NSObject, UIDocumentPickerDelegate {
    var onPick: ((URL) -> Void)?
    var onCancel: (() -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            onCancel?()
            return
        }
        onPick?(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel?()
    }
}

@MainActor
private enum SystemPresenter {
    static func share(file url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let presenter = topViewController(),
           let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        present(activity)
    }

    static func present(_ controller: UIViewController) {
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
