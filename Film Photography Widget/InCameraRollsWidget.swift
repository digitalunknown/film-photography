import SwiftUI
import WidgetKit

struct InCameraRollsEntry: TimelineEntry {
    let date: Date
    let rows: [InCameraRollRow]
    let totalCount: Int
}

struct InCameraRollsProvider: TimelineProvider {
    func placeholder(in context: Context) -> InCameraRollsEntry {
        InCameraRollsEntry(
            date: Date(),
            rows: [
                InCameraRollRow(
                    id: UUID(),
                    stockName: "Kodak Portra 400",
                    cameraName: "Leica M6",
                    statusLabel: "In camera",
                    frameCount: 12,
                    totalExposures: 36,
                    imageName: "roll_kodak"
                ),
                InCameraRollRow(
                    id: UUID(),
                    stockName: "Ilford HP5 Plus",
                    cameraName: "Nikon F3",
                    statusLabel: "Shot, undeveloped",
                    frameCount: 36,
                    totalExposures: 36,
                    imageName: "roll_ilford"
                ),
                InCameraRollRow(
                    id: UUID(),
                    stockName: "Fujifilm Superia 400",
                    cameraName: "",
                    statusLabel: "In stock",
                    frameCount: 0,
                    totalExposures: 36,
                    imageName: "roll_fujifilm"
                ),
            ],
            totalCount: 3
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (InCameraRollsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InCameraRollsEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> InCameraRollsEntry {
        let loaded = InCameraRollsLoader.loadRows()
        return InCameraRollsEntry(date: Date(), rows: loaded.rows, totalCount: loaded.totalCount)
    }
}

struct InCameraRollsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var entry: InCameraRollsEntry

    private var usesGrid: Bool {
        entry.totalCount >= InCameraRollsLoader.gridLimit
    }

    private var plateSize: CGFloat {
        if usesGrid { return family == .systemLarge ? 44 : 32 }
        return family == .systemLarge ? 56 : 44
    }

    private var rowSpacing: CGFloat {
        if usesGrid { return family == .systemLarge ? 10 : 6 }
        return family == .systemLarge ? 10 : 8
    }

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                emptyState
            } else if usesGrid {
                rollGrid
            } else {
                rollList
            }
        }
        .containerBackground(for: .widget) {
            AppPalette.bg
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("No rolls in the pipeline.")
                .font(widgetFont(13))
                .foregroundStyle(AppPalette.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var rollList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entry.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(AppPalette.rule)
                        .frame(height: 1)
                }
                rollRow(row)
                    .padding(.vertical, rowSpacing)
            }

            overflowLabel

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var rollGrid: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(gridRows, id: \.self) { pair in
                HStack(alignment: .center, spacing: 12) {
                    ForEach(pair, id: \.id) { row in
                        rollRow(row, compact: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if pair.count == 1 {
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            overflowLabel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemLarge ? 16 : 12)
    }

    /// Six rolls as three pairs, left-to-right then down — same reading order as the list.
    private var gridRows: [[InCameraRollRow]] {
        stride(from: 0, to: entry.rows.count, by: 2).map { start in
            Array(entry.rows[start..<min(start + 2, entry.rows.count)])
        }
    }

    @ViewBuilder
    private var overflowLabel: some View {
        if entry.totalCount > entry.rows.count {
            Text("+\(entry.totalCount - entry.rows.count) more")
                .font(widgetFont(11))
                .foregroundStyle(AppPalette.textSecondary)
                .padding(.top, usesGrid ? 0 : 8)
        }
    }

    private func rollRow(_ row: InCameraRollRow, compact: Bool = false) -> some View {
        HStack(alignment: .center, spacing: compact ? 8 : 16) {
            rollThumbnail(row.imageName)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.stockName)
                    .font(widgetFont(compact ? 12 : 13))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                cameraAndStatus(row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.showsExposures {
                Text(row.exposuresLabel)
                    .font(widgetFont(compact ? 11 : 13))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
        }
    }

    /// Camera on the left, status beside it — the same pairing as the list row, just
    /// condensed for the widget.
    private func cameraAndStatus(_ row: InCameraRollRow) -> some View {
        HStack(spacing: 6) {
            if !row.cameraName.isEmpty {
                Text(row.cameraName)
                    .lineLimit(1)
            }
            Text(row.statusLabel)
                .lineLimit(1)
        }
        .font(widgetFont(11))
        .foregroundStyle(AppPalette.textSecondary)
    }

    private func rollThumbnail(_ imageName: String?) -> some View {
        ZStack {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppPalette.surface)
                Image(systemName: "film")
                    .font(.system(size: 16))
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .frame(width: plateSize, height: plateSize)
        .clipped()
    }

    /// Mirrors `InstrumentFont` (Figtree + 1pt size bump).
    private func widgetFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold:
            name = "Figtree-SemiBold"
        case .bold, .heavy, .black:
            name = "Figtree-Bold"
        case .medium:
            name = "Figtree-Medium"
        default:
            name = "Figtree-Regular"
        }
        return .custom(name, size: size)
    }
}

struct InCameraRollsWidget: Widget {
    let kind = AppGroupStorage.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InCameraRollsProvider()) { entry in
            InCameraRollsWidgetView(entry: entry)
        }
        .configurationDisplayName("My Film")
        .description("Your rolls in pipeline order, with how many frames you’ve shot.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
