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
                                message: "No rolls in the pipeline.",
                                primaryAction: "Choose from library",
                                primaryHandler: { store.addRollEntry = .library },
                                secondaryAction: "Add manually",
                                secondaryHandler: { store.addRollEntry = .manual }
                            )
                            .padding(.horizontal, AppTheme.horizontalPadding)
                            .padding(.top, AppTheme.Spacing.sm)
                        } else {
                            ForEach(Array(visibleSections.enumerated()), id: \.element.status) { index, section in
                                if index > 0 {
                                    HairlineRule()
                                        .padding(.horizontal, AppTheme.horizontalPadding)
                                        .padding(.vertical, AppTheme.Spacing.lg)
                                }

                                rollSection(status: section.status, rolls: section.rolls, isFirst: index == 0)
                            }
                        }

                        if !store.archivedRolls.isEmpty {
                            archiveLink
                        }
                    }
                    .padding(.bottom, store.pendingDeletion != nil ? AppTheme.Spacing.xl + AppTheme.Spacing.lg : AppTheme.Spacing.xl)
                }

                if let pending = store.pendingDeletion {
                    UndoDeletionBanner(rollLabel: store.label(for: pending.roll)) {
                        store.undoDelete()
                    }
                }
            }
            .instrumentScreen()
            .instrumentTabNavigation(title: "My Film")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.showingSettings = true
                    } label: {
                        LucideIcon(.fileText)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Choose from library", lucide: .library) {
                            store.addRollEntry = .library
                        }
                        .font(AppType.body)
                        Button("Add manually", lucide: .fileText) {
                            store.addRollEntry = .manual
                        }
                        .font(AppType.body)
                    } label: {
                        LucideIcon(.plus)
                    }
                    .accessibilityLabel("Add roll")
                }
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
            return "\(store.label(for: roll)) is loaded in a camera. You can undo for 5 seconds."
        }
        return "\(store.label(for: roll)) will be removed. You can undo for 5 seconds."
    }

    private var archiveLink: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, AppTheme.Spacing.lg)

            NavigationLink {
                ArchiveRollsView()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    SectionLabel(title: "Archive")
                    Spacer()
                    Text("\(store.archivedRolls.count)")
                        .font(AppType.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                    LucideIcon(.chevronRight)
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

    /// Most recently added first. Rolls are appended as they are created, so the
    /// store's own order is the order they arrived in.
    private func rolls(for status: RollStatus) -> [Roll] {
        Array(
            store.activeRolls
                .filter { $0.status.normalized == status }
                .reversed()
        )
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
                        Button(destructive: "Delete", lucide: .trash) {
                            rollToDelete = roll
                        }
                        .font(AppType.body)
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
