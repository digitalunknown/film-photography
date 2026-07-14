import SwiftUI

struct RollsTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedRoll: Roll?
    @State private var rollToDelete: Roll?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.activeRolls.isEmpty {
                            InstrumentEmptyState(
                                message: "No rolls in the pipeline. Tap + to add a roll.",
                                primaryAction: "Add roll →",
                                primaryHandler: { store.showingAddRoll = true }
                            )
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.top, AppTheme.Spacing.sm)
                        } else {
                            ForEach(Array(visibleSections.enumerated()), id: \.element.status) { index, section in
                                if index > 0 {
                                    SectionRule()
                                        .padding(.horizontal, AppTheme.horizontalPadding)
                                        .padding(.vertical, AppTheme.Spacing.md)
                                }

                                rollSection(status: section.status, rolls: section.rolls, isFirst: index == 0)
                            }
                        }

                        if !store.archivedRolls.isEmpty {
                            archiveLink
                        }
                    }
                    .padding(.bottom, store.pendingDeletion != nil ? AppTheme.Spacing.xl + AppTheme.Spacing.md : AppTheme.Spacing.xl)
                }

                if let pending = store.pendingDeletion {
                    UndoDeletionBanner(rollLabel: pending.roll.shortId) {
                        store.undoDelete()
                    }
                }
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "My Film") {
                store.showingAddRoll = true
            }
            .navigationDestination(item: $selectedRoll) { roll in
                RollDetailView(rollId: roll.id)
            }
            .navigationDestination(for: Roll.self) { roll in
                RollDetailView(rollId: roll.id)
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
            SectionRule()
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, AppTheme.Spacing.md)

            NavigationLink {
                ArchiveRollsView()
            } label: {
                HStack {
                    Text("ARCHIVE")
                        .font(InstrumentFont.mono(12, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .tracking(1.0)
                    Spacer()
                    Text("\(store.archivedRolls.count) →")
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, AppTheme.Spacing.sm)
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

    private func rollSection(status: RollStatus, rolls: [Roll], isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "\(status.sectionTitle) (\(rolls.count))")
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, isFirst ? AppTheme.Spacing.sm : 0)
                .padding(.bottom, AppTheme.Spacing.sm)

            ForEach(Array(rolls.enumerated()), id: \.element.id) { index, roll in
                RollLedgerRow(roll: roll)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRoll = roll }
                    .contextMenu {
                        Button(role: .destructive) {
                            rollToDelete = roll
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.vertical, AppTheme.Spacing.sm)

                if index < rolls.count - 1 {
                    HairlineRule()
                        .padding(.horizontal, AppTheme.horizontalPadding)
                }
            }
        }
    }
}

#Preview {
    RollsTabView()
        .environment(AppStore())
}
