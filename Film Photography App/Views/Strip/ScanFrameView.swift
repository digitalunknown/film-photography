import SwiftUI

struct ScanFrameView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let rollId: UUID
    let frame: StripFrame
    let stock: FilmStock?

    @State private var showingDeleteConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fileName = frame.scanFileName,
               let image = ScanStorage.thumbnail(for: rollId, fileName: fileName, maxSize: 4096) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }

            VStack {
                Spacer()
                metadataBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppTheme.Spacing.md) {
                    if frame.scanFileName != nil {
                        Button("Delete", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                    }
                    Button("Done") { dismiss() }
                        .font(InstrumentFont.mono(13))
                }
            }
        }
        .alert("Delete photo?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                guard let fileName = frame.scanFileName else { return }
                store.removeScan(from: rollId, fileName: fileName)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the scan from this roll.")
        }
    }

    private var metadataBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frame \(frame.index)")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(Color.white)
            if let marker = frame.marker {
                Text(DateFormatters.telemetry.string(from: marker.timestamp))
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(Color.white.opacity(0.75))
                if marker.latitude != 0 || marker.longitude != 0 {
                    Text(String(format: "%.4f, %.4f", marker.latitude, marker.longitude))
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            if let stock {
                Text(stock.name)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.black.opacity(0.55))
    }
}
