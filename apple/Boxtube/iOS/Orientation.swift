import UIKit

/// Which way the iPhone UI may turn. Boxtube stays portrait except on the Watch screen, where turning
/// the phone (or the full screen button, or swiping up on the video) shows the video full screen.
@MainActor
enum Orientation {
    /// Read by the app delegate.
    static var allowed: UIInterfaceOrientationMask = .portrait
    /// After the app turns the screen itself, the phone may still be held the other way; hold the new
    /// orientation until the phone is actually turned to match, so it doesn't snap straight back.
    private static var waitingFor: UIInterfaceOrientationMask?
    private static var observer: NSObjectProtocol?
    private static var onWatchScreen = false

    /// The Watch screen is up: let the phone turn it.
    static func allowRotation(_ on: Bool) {
        waitingFor = nil
        onWatchScreen = on
        if on {
            allowed = .allButUpsideDown
            startWatchingDevice()
        } else {
            allowed = .portrait
            request(.portrait)
        }
        refresh()
    }

    static func setFullScreen(_ on: Bool) {
        let target: UIInterfaceOrientationMask = on ? .landscapeRight : .portrait
        allowed = on ? .landscape : .portrait
        waitingFor = on ? .landscape : .portrait
        refresh()
        request(target)
    }

    private static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var vc = window.rootViewController
                while let current = vc {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    vc = current.presentedViewController
                }
            }
        }
    }

    private static func startWatchingDevice() {
        guard observer == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard onWatchScreen, let wanted = waitingFor else { return }
                let d = UIDevice.current.orientation
                let matches = wanted == .landscape ? d.isLandscape : d == .portrait
                // Once the phone is held the way the screen already is, let it turn freely again.
                if matches {
                    waitingFor = nil
                    allowed = .allButUpsideDown
                    refresh()
                }
            }
        }
    }
}

final class BoxtubeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Orientation.allowed }
    }
}
