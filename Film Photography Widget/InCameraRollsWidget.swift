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
            rows: Array(Self.sampleRows.prefix(visibleLimit(for: context.family))),
            totalCount: Self.sampleRows.count
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (InCameraRollsEntry) -> Void) {
        completion(makeEntry(family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InCameraRollsEntry>) -> Void) {
        let entry = makeEntry(family: context.family)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry(family: WidgetFamily) -> InCameraRollsEntry {
        let loaded = InCameraRollsLoader.loadRows(maxVisible: visibleLimit(for: family))
        return InCameraRollsEntry(date: Date(), rows: loaded.rows, totalCount: loaded.totalCount)
    }

    private func visibleLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall, .systemMedium: 4
        case .systemLarge, .systemExtraLarge: 8
        default: 4
        }
    }

    private static let sampleRows = [
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
            stockName: "CineStill 800T",
            cameraName: "Contax T2",
            statusLabel: "In camera",
            frameCount: 8,
            totalExposures: 36,
            imageName: "roll_cinestill_800t"
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
    ]
}

struct InCameraRollsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var entry: InCameraRollsEntry

    private var columns: Int {
        family == .systemSmall ? 2 : 4
    }

    private var rowCount: Int {
        switch family {
        case .systemSmall, .systemLarge, .systemExtraLarge: 2
        default: 1
        }
    }

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                emptyState
            } else {
                ringGrid
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

    /// Small matches Figma 276:782 — 2×2 rings with the count pill on the ring.
    /// Medium is one row of four; large is two rows, both with count + camera below.
    private var ringGrid: some View {
        VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { rowIndex in
                HStack(spacing: family == .systemMedium ? 16 : 12) {
                    ForEach(0..<columns, id: \.self) { columnIndex in
                        let index = rowIndex * columns + columnIndex
                        Group {
                            if entry.rows.indices.contains(index) {
                                let row = entry.rows[index]
                                Link(destination: AppDeepLink.roll(row.id)) {
                                    RollRingCell(row: row, family: family)
                                }
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(family == .systemSmall ? 20 : 16)
    }

    private func widgetFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        RollRingCell.widgetFont(size, weight: weight)
    }
}

/// One roll as a progress ring with the canister in the middle.
private struct RollRingCell: View {
    let row: InCameraRollRow
    let family: WidgetFamily

    private var progress: CGFloat {
        min(CGFloat(row.frameCount) / CGFloat(max(row.totalExposures, 1)), 1)
    }

    private var showsCamera: Bool {
        family != .systemSmall
    }

    private var labelSize: CGFloat {
        switch family {
        case .systemSmall: 10
        case .systemLarge, .systemExtraLarge: 16
        default: 15
        }
    }

    private var cameraSize: CGFloat { 11 }

    var body: some View {
        GeometryReader { geo in
            if family == .systemSmall {
                smallCell(in: geo.size)
            } else {
                labeledCell(in: geo.size)
            }
        }
    }

    /// Figma small (276:782): 60pt ring, 4pt stroke, 50pt canister, 8pt pill on the ring.
    private func smallCell(in size: CGSize) -> some View {
        let diameter = min(size.width, size.height)
        let lineWidth = max(3.5, diameter * (4.0 / 60.0))
        let imageSize = max(20, diameter * (50.0 / 60.0))
        // Badge top sits at 52pt on a 60pt ring and hangs ~4.5pt below the stroke.
        let pillHang = diameter * (4.5 / 60.0)

        return ZStack {
            ZStack(alignment: .bottom) {
                ZStack {
                    ring(diameter: diameter, lineWidth: lineWidth)
                    rollImage(size: imageSize)
                }
                .frame(width: diameter, height: diameter)

                countPill
                    .offset(y: pillHang)
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: size.width, height: size.height)
    }

    private func labeledCell(in size: CGSize) -> some View {
        let countHeight: CGFloat = 18
        let cameraHeight: CGFloat = showsCamera ? 14 : 0
        let gap: CGFloat = 6
        let captionHeight = countHeight + (showsCamera ? 2 + cameraHeight : 0)
        let diameter = min(size.width, max(24, size.height - captionHeight - gap))
        let lineWidth = max(3.5, diameter * 0.09)
        let imageSize = max(16, (diameter - lineWidth * 2) * 0.92)

        return VStack(spacing: gap) {
            ZStack {
                ring(diameter: diameter, lineWidth: lineWidth)
                rollImage(size: imageSize)
            }
            .frame(width: diameter, height: diameter)

            VStack(spacing: 2) {
                Text(row.exposuresLabel)
                    .font(Self.widgetFont(labelSize))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .frame(height: countHeight)

                if showsCamera {
                    Text(row.cameraName)
                        .font(Self.widgetFont(cameraSize))
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .frame(height: cameraHeight)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func ring(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(
                    AppPalette.well,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppPalette.textPrimary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private var countPill: some View {
        Text(row.exposuresLabel)
            .font(Self.widgetFont(8, weight: .semibold))
            .foregroundStyle(AppPalette.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.25)
            .background(AppPalette.bg, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(AppPalette.textPrimary, lineWidth: 1.25)
            }
    }

    @ViewBuilder
    private func rollImage(size: CGFloat) -> some View {
        if let imageName = row.imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "film")
                .font(.system(size: size * 0.45, weight: .regular))
                .foregroundStyle(AppPalette.textPrimary)
        }
    }

    static func widgetFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
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
        .description("How many frames you’ve shot on each roll.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    InCameraRollsWidget()
} timeline: {
    InCameraRollsEntry(
        date: .now,
        rows: [
            InCameraRollRow(
                id: UUID(),
                stockName: "Kodak Portra 400",
                cameraName: "Leica M6",
                statusLabel: "In camera",
                frameCount: 12,
                totalExposures: 24,
                imageName: "roll_kodak"
            ),
            InCameraRollRow(
                id: UUID(),
                stockName: "CineStill 400D",
                cameraName: "Nikon F3",
                statusLabel: "In camera",
                frameCount: 12,
                totalExposures: 24,
                imageName: "roll_cinestill_400d"
            ),
            InCameraRollRow(
                id: UUID(),
                stockName: "Fujifilm Superia 400",
                cameraName: "Contax T2",
                statusLabel: "In camera",
                frameCount: 12,
                totalExposures: 24,
                imageName: "roll_fujifilm"
            ),
            InCameraRollRow(
                id: UUID(),
                stockName: "Kodak Portra 400",
                cameraName: "",
                statusLabel: "In camera",
                frameCount: 12,
                totalExposures: 24,
                imageName: "roll_kodak"
            ),
        ],
        totalCount: 4
    )
}

#Preview("Medium", as: .systemMedium) {
    InCameraRollsWidget()
} timeline: {
    InCameraRollsEntry(
        date: .now,
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
                stockName: "CineStill 800T",
                cameraName: "Contax T2",
                statusLabel: "In camera",
                frameCount: 8,
                totalExposures: 36,
                imageName: "roll_cinestill_800t"
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
        totalCount: 4
    )
}
