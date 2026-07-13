import SwiftUI

struct RollsTabView: View {
    @Environment(AppStore.self) private var store
    @State private var rollToDelete: Roll?
    @State private var showingArchive = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.pipelineSummary)
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.bottom, 16)

                        HairlineRule()
                            .padding(.horizontal, AppTheme.horizontalPadding)

                        if store.activeRolls.isEmpty {
                            InstrumentEmptyState(
                                message: "No rolls in the pipeline. Tap + to add a roll.",
                                primaryAction: "Add roll →",
                                primaryHandler: { store.showingAddRoll = true }
                            )
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.top, AppTheme.sectionSpacing)
                        } else {
                            ForEach(Array(visibleSections.enumerated()), id: \.element.status) { index, section in
                                if index > 0 {
                                    HairlineRule()
                                        .padding(.horizontal, AppTheme.horizontalPadding)
                                        .padding(.top, AppTheme.sectionSpacing)
                                }

                                rollSection(status: section.status, rolls: section.rolls)
                            }
                        }

                        archiveLink
                    }
                    .padding(.bottom, store.pendingDeletion != nil ? 80 : 32)
                }

                if let pending = store.pendingDeletion {
                    UndoDeletionBanner(rollLabel: pending.roll.shortId) {
                        store.undoDelete()
                    }
                }
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "Rolls") {
                store.showingAddRoll = true
            }
            .navigationDestination(for: Roll.self) { roll in
                RollDetailView(rollId: roll.id)
            }
            .navigationDestination(isPresented: $showingArchive) {
                ArchiveRollsView()
            }
            .alert(deleteAlertTitle, isPresented: deleteRollBinding) {
                Button("Delete", role: .destructive) {
                    if let roll = rollToDelete {
                        store.requestDeleteRoll(roll.id)
                    }
                    rollToDelete = nil
                }
                Button("Cancel", role: .cancel) { rollToDelete = nil }
            } message: {
                if let roll = rollToDelete {
                    Text(deleteMessage(for: roll))
                }
            }
        }
    }

    private var deleteRollBinding: Binding<Bool> {
        Binding(
            get: { rollToDelete != nil },
            set: { if !$0 { rollToDelete = nil } }
        )
    }

    private var deleteAlertTitle: String {
        rollToDelete?.status == .inCamera ? "Delete active roll?" : "Delete roll?"
    }

    private func deleteMessage(for roll: Roll) -> String {
        if roll.status == .inCamera {
            return "\(roll.shortId) is loaded in a camera. You can undo for 5 seconds."
        }
        return "\(roll.shortId) will be removed. You can undo for 5 seconds."
    }

    private var archiveLink: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, AppTheme.sectionSpacing)

            Button {
                showingArchive = true
            } label: {
                HStack {
                    Text("Archive")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("\(store.archivedRolls.count) →")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, AppTheme.rowSpacing)
            }
            .buttonStyle(.plain)
        }
    }

    private var visibleSections: [(status: RollStatus, rolls: [Roll])] {
        RollStatus.activePipelineCases.compactMap { status in
            let statusRolls = rolls(for: status)
            return statusRolls.isEmpty ? nil : (status, statusRolls)
        }
    }

    private func rolls(for status: RollStatus) -> [Roll] {
        store.activeRolls
            .filter { $0.status.normalized == status }
            .sorted { $0.shortId > $1.shortId }
    }

    private func rollSection(status: RollStatus, rolls: [Roll]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: status.sectionTitle)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, 16)

            ForEach(Array(rolls.enumerated()), id: \.element.id) { index, roll in
                NavigationLink(value: roll) {
                    RollLedgerRow(roll: roll)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        rollToDelete = roll
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, AppTheme.rowSpacing)

                if index < rolls.count - 1 {
                    HairlineRule()
                        .padding(.horizontal, AppTheme.horizontalPadding)
                }
            }
        }
    }
}

private struct RollLedgerRow: View {
    @Environment(AppStore.self) private var store
    let roll: Roll

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RollPlate(tint: stock?.emulsionTint ?? AppTheme.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                Text(rowPrimary)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let rowSecondary {
                    Text(rowSecondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(rowValue)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let rowValueSecondary {
                    Text(rowValueSecondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(itemExpiryStyle)
                }
            }
        }
    }

    private var itemExpiryStyle: Color {
        if roll.isExpired || roll.isNearExpiry { return AppTheme.textPrimary }
        return AppTheme.textSecondary
    }

    private var stock: FilmStock? {
        store.stock(for: roll.stockId)
    }

    private var rowPrimary: String {
        if let stock = store.stock(for: roll.stockId) {
            return stock.name
        }
        return roll.shortId
    }

    private var rowSecondary: String? {
        var parts: [String] = [roll.shortId, roll.format.displayName]
        if roll.status.showsCamera, let camera = store.camera(for: roll.cameraId) {
            parts.append(camera.name)
        }
        if !roll.tags.isEmpty {
            parts.append(roll.tags.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private var rowValue: String {
        switch roll.status.normalized {
        case .inFridge: "In fridge"
        case .inCamera: "\(roll.frameCount)/\(roll.totalExposures)"
        case .shotUndeveloped: roll.storageLocation ?? "Waiting"
        case .scanned: "Import"
        case .atLab: roll.labName ?? "At lab"
        default: roll.status.displayName
        }
    }

    private var rowValueSecondary: String? {
        switch roll.status.normalized {
        case .inFridge:
            if roll.isExpired { return "Expired" }
            if roll.isNearExpiry { return "Exp soon" }
            if let expiry = roll.expiryDate {
                return "Exp \(DateFormatters.short.string(from: expiry))"
            }
            return nil
        case .scanned:
            if let date = roll.scannedDate {
                return DateFormatters.short.string(from: date)
            }
            return nil
        default:
            return nil
        }
    }
}

#Preview {
    RollsTabView()
        .environment(AppStore())
}
