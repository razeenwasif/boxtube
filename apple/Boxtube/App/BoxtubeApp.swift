import SwiftUI
import BoxtubeCore
import BoxtubeUI

@main
struct BoxtubeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            PhoneRoot()
                .environment(model)
                .bxMenuHost()
                .preferredColorScheme(.dark)
                .onOpenURL { model.handle($0) }
                .task { await model.start() }
        }
        #else
        WindowGroup("Boxtube", id: "main") {
            MacRoot()
                .environment(model)
                .bxMenuHost()
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { model.handle($0) }
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1440, height: 900)
        .commands { MacCommands(model: model) }

        Window("Floating player", id: "floating") {
            FloatingPlayerWindow()
                .environment(model)
                .bxMenuHost()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            let size = CGSize(width: 400, height: 225)
            return WindowPlacement(CGPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24), size: size)
        }
        .windowLevel(.floating)

        // The menu bar icon is an AppKit status item (MenuBarStatusItem), installed by AppModel.start().

        Settings {
            MacSettings().environment(model).bxMenuHost().preferredColorScheme(.dark)
        }
        #endif
    }
}
