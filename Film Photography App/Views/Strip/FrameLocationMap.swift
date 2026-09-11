import MapKit
import SwiftUI

/// Static preview of where a frame was shot. The pin is the mark; the map is the ground.
struct FrameLocationMap: View {
    let coordinate: CLLocationCoordinate2D

    private var position: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 420,
                longitudinalMeters: 420
            )
        )
    }

    var body: some View {
        Map(position: .constant(position), interactionModes: []) {
            Annotation("", coordinate: coordinate, anchor: .center) {
                ZStack {
                    Circle()
                        .fill(AppTheme.bg)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: AppTheme.strokeWidth)
                        }
                    LucideIcon(.camera, size: 16)
                        .foregroundStyle(Color.white)
                }
                .frame(width: 36, height: 36)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.sm))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
