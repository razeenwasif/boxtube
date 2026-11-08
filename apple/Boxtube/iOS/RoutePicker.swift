import SwiftUI
import AVKit
import BoxtubeUI

/// The mockup's cast button: a 40 pt circle with the cast glyph, backed by the system AirPlay route picker.
struct CastButton: View {
    var size: CGFloat = 40
    var fill: Color = BX.surface2
    var body: some View {
        ZStack {
            Circle().fill(fill)
            IconView(.cast, size: 19, lineWidth: 1.8).foregroundStyle(BX.text)
            RoutePicker().opacity(0.02)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cast to a device")
        .accessibilityAddTraits(.isButton)
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
