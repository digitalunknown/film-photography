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
                    frameCount: 12,
                    totalExposures: 36,
                    imageName: "roll_kodak"
                ),
                InCameraRollRow(
                    id: UUID(),
                    stockName: "Ilford HP5 Plus",
                    cameraName: "Nikon F3",
                    frameCount: 5,
                    totalExposures: 36,
                    imageName: "roll_ilford"
                ),
                InCameraRollRow(
                    id: UUID(),
                    stockName: "Fujifilm Superia 400",
                    cameraName: "Olympus XA",
                    frameCount: 24,
                    totalExposures: 36,
                    imageName: "roll_fujifilm"
                ),
            ],
            totalCount: 3
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
        let maxVisible = Self.maxVisibleRows(for: family)
        let loaded = InCameraRollsLoader.loadRows(maxVisible: maxVisible)
        return InCameraRollsEntry(date: Date(), rows: loaded.rows, totalCount: loaded.totalCount)
    }

    static func maxVisibleRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemLarge:
            return 8
        default:
            return 4
        }
    }
}

struct InCameraRollsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var entry: InCameraRollsEntry

    private var plateSize: CGFloat {
        family == .systemLarge ? 56 : 44
    }

    private var rowSpacing: CGFloat {
        family == .systemLarge ? 10 : 8
    }

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                emptyState
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
            Text("No rolls in camera")
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

            if entry.totalCount > entry.rows.count {
                Text("+\(entry.totalCount - entry.rows.count) more")
                    .font(widgetFont(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private func rollRow(_ row: InCameraRollRow) -> some View {
        HStack(alignment: .center, spacing: 16) {
            rollThumbnail(row.imageName)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.stockName)
                    .font(widgetFont(13))
                    .foregroundStyle(AppPalette.textPrimary)
                    .lineLimit(1)
                Text(row.cameraName)
                    .font(widgetFont(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.exposuresLabel)
                .font(widgetFont(13))
                .foregroundStyle(AppPalette.textPrimary)
                .monospacedDigit()
                .layoutPriority(1)
        }
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
        .configurationDisplayName("In Camera")
        .description("Film rolls currently loaded and how many exposures you’ve taken.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
