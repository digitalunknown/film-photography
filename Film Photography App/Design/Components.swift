import SwiftUI
import UIKit

// MARK: - Structure

struct HairlineRule: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.rule)
            .frame(height: 0.5)
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "+"

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(InstrumentFont.display(32, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(InstrumentFont.mono(20))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(AppTheme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(InstrumentFont.mono(12, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .tracking(0.6)
            .padding(.top, 8)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    var valueBright: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(valueBright ? AppTheme.textPrimary : AppTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct LedgerRowHeader: View {
    let glyph: String
    let primary: String
    let secondary: String?
    let value: String
    var valueSecondary: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(glyph)
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(primary)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let secondary {
                    Text(secondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let valueSecondary {
                    Text(valueSecondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}

struct DisclosureBlock<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.leading, 22)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct TextAction: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.rule)
        }
        .buttonStyle(.plain)
    }
}

struct InstrumentEmptyState: View {
    let message: String
    var primaryAction: String
    var primaryHandler: () -> Void
    var secondaryAction: String? = nil
    var secondaryHandler: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(message)
                .font(InstrumentFont.mono(13))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                TextAction(label: primaryAction, action: primaryHandler)
                if let secondaryAction, let secondaryHandler {
                    TextAction(label: secondaryAction, action: secondaryHandler)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 48)
    }
}

struct FilterTextRow: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .font(InstrumentFont.mono(12))
                            .foregroundStyle(selection == option ? AppTheme.textPrimary : AppTheme.textTertiary)
                            .underline(selection == option, color: AppTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct UnderlineMeter: View {
    let label: String
    let value: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.rule).frame(height: 0.5)
                    Rectangle().fill(AppTheme.textPrimary).frame(width: geo.size.width * progress, height: 0.5)
                }
            }
            .frame(height: 0.5)
        }
    }
}

struct SkeletalBarChart: View {
    let values: [Double]
    let labels: [String]
    var maxValue: Double?

    private var ceiling: Double {
        maxValue ?? (values.max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(value > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 2, height: max(4, CGFloat(value / max(ceiling, 1)) * 64))
                    Text(labels[index])
                        .font(InstrumentFont.mono(10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 88)
    }
}

struct HeroMetric: View {
    let label: String
    let sublabel: String?
    let value: String

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textPrimary)
                if let sublabel {
                    Text(sublabel)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(InstrumentFont.display(52, weight: .light))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

struct GhostCircleButton: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InstrumentFont.mono(16))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(AppTheme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct DetailBackHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            GhostCircleButton(label: "‹") { dismiss() }
            Spacer()
        }
        .padding(.bottom, 20)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: title)
            content()
            HairlineRule()
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
    }
}

struct InstrumentDetailChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .instrumentScreen()
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func instrumentDetailChrome() -> some View {
        modifier(InstrumentDetailChrome())
    }
}

struct StockPlate: View {
    let name: String
    let shortCode: String
    let tint: Color
    var square: Bool = true
    var height: CGFloat = 160

    init(stock: FilmStock, square: Bool = true, height: CGFloat = 160) {
        self.name = stock.name
        self.shortCode = stock.shortCode
        self.tint = stock.emulsionTint
        self.square = square
        self.height = height
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(0.22))
            Rectangle()
                .strokeBorder(AppTheme.rule, lineWidth: 0.5)
            Text(shortCode)
                .font(InstrumentFont.mono(square ? 22 : 28))
                .foregroundStyle(tint.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .modifier(StockPlateSizing(square: square, height: height))
        .accessibilityLabel("\(name) plate")
    }
}

private struct StockPlateSizing: ViewModifier {
    let square: Bool
    let height: CGFloat

    func body(content: Content) -> some View {
        if square {
            content.aspectRatio(1, contentMode: .fit)
        } else {
            content.frame(height: height)
        }
    }
}

struct RollPlate: View {
    var tint: Color = AppTheme.textTertiary
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(0.18))
            Rectangle()
                .strokeBorder(AppTheme.rule, lineWidth: 0.5)
            Text("◎")
                .font(InstrumentFont.mono(size * 0.32))
                .foregroundStyle(tint.opacity(0.85))
        }
        .frame(width: size, height: size)
    }
}

struct CameraPhotoPlate: View {
    var photoData: Data? = nil
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().strokeBorder(AppTheme.rule, lineWidth: 0.5)
                    Text("◻")
                        .font(InstrumentFont.mono(size * 0.28))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

struct PipelineStatusRow: View {
    let status: String
    var onTapStatus: () -> Void

    var body: some View {
        Button(action: onTapStatus) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(status)
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer(minLength: 16)
                Text("Change →")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct UndoDeletionBanner: View {
    let rollLabel: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rollLabel) deleted")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button("Undo", action: onUndo)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.textPrimary)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 12)
        .background(AppTheme.rule)
    }
}

struct EditableDateRow: View {
    let label: String
    @Binding var date: Date
    var hasDate: Bool
    var onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { hasDate }, set: onToggle)) {
                Text(label)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(AppTheme.textPrimary)

            if hasDate {
                DatePicker(label, selection: $date)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }
}

struct InstrumentFormBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func instrumentFormStyle() -> some View {
        modifier(InstrumentFormBackground())
    }
}
