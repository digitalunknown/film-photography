import SwiftUI

struct ScanFrameView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let rollId: UUID
    let frame: StripFrame
    let stock: FilmStock?

    @State private var showingDeleteConfirm = false

    private var image: UIImage? {
        guard let fileName = frame.scanFileName else { return nil }
        return ScanStorage.thumbnail(for: rollId, fileName: fileName, maxSize: 4096)
    }

    private var hasRemovablePhoto: Bool {
        guard frame.scanFileName != nil else { return false }
        if store.roll(for: rollId)?.framePhotoFileName(forFrame: frame.index) != nil {
            return true
        }
        return store.roll(for: rollId)?.scanFileNames.contains(frame.scanFileName ?? "") == true
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(String(format: "%02d", frame.index))
                    .font(InstrumentFont.mono(72, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.18))
            }

            VStack {
                Spacer()
                metadataBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .accessibilityLabel("Close")
            }
            if hasRemovablePhoto {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                }
            }
        }
        .alert("Delete photo?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if store.roll(for: rollId)?.framePhotoFileName(forFrame: frame.index) != nil {
                    store.removeFramePhoto(from: rollId, frameIndex: frame.index)
                } else if let fileName = frame.scanFileName {
                    store.removeScan(from: rollId, fileName: fileName)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the photo from frame \(frame.index).")
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
