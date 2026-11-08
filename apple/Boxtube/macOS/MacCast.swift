import SwiftUI
import AVKit
import BoxtubeUI

/// Cast button from the Mac artboards (36 pt), backed by the system AirPlay route picker.
struct MacCastButton: View {
    var body: some View {
        ZStack {
            IconView(.cast, size: 19, lineWidth: 1.8).foregroundStyle(BX.text2)
            Picker().opacity(0.02)
        }
        .frame(width: 36, height: 36)
        .help("Cast to a device")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cast to a device")
        .accessibilityAddTraits(.isButton)
    }

    private struct Picker: NSViewRepresentable {
        func makeNSView(context: Context) -> AVRoutePickerView {
            let v = AVRoutePickerView()
            v.isRoutePickerButtonBordered = false
            return v
        }
        func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
    }
}
