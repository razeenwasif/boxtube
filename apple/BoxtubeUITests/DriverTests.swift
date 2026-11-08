import XCTest

/// Drives Boxtube on a real iPhone from a list of steps passed in the BOXTUBE_STEPS environment variable
/// (set TEST_RUNNER_BOXTUBE_STEPS when calling xcodebuild). Each step is one of:
///   {"launch":true} {"activate":true} {"tap":"Accessibility label"} {"tapXY":[x,y]} {"swipe":"up|down|left|right"}
///   {"type":"text"} {"wait":seconds} {"shot":"name"} {"dump":true}
///   {"drag":[x1,y1,x2,y2]} {"press":"label"} {"pressXY":[x,y]} {"home":true} {"lock":true}
/// Screenshots and hierarchy dumps are saved as test attachments.
final class DriverTests: XCTestCase {
    func testDrive() throws {
        let app = XCUIApplication(bundleIdentifier: "com.razeenwasif.boxtube")
        let raw = ProcessInfo.processInfo.environment["BOXTUBE_STEPS"] ?? #"[{"launch":true},{"wait":4},{"shot":"home"}]"#
        let steps = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] ?? []
        for (i, step) in steps.enumerated() {
            if step["launch"] != nil { app.launch() }
            if step["activate"] != nil { app.activate() }
            if let label = step["tap"] as? String {
                let element = app.descendants(matching: .any)[label].firstMatch
                if element.waitForExistence(timeout: 5) { element.tap() } else { attachText("missing-\(i)", "No element labelled \(label)") }
            }
            if let xy = step["tapXY"] as? [Double], xy.count == 2 {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            }
            if let dir = step["swipe"] as? String {
                switch dir {
                case "up": app.swipeUp()
                case "down": app.swipeDown()
                case "left": app.swipeLeft()
                default: app.swipeRight()
                }
            }
            // Points, like tapXY: [x1, y1, x2, y2]. Starting at x≈1 is an edge swipe.
            if let d = step["drag"] as? [Double], d.count == 4 {
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: d[0], dy: d[1]))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: d[2], dy: d[3])), withVelocity: .default, thenHoldForDuration: 0.1)
            }
            if let label = step["press"] as? String {
                let element = app.descendants(matching: .any)[label].firstMatch
                if element.waitForExistence(timeout: 5) { element.press(forDuration: 1.2) } else { attachText("missing-\(i)", "No element labelled \(label)") }
            }
            if let xy = step["pressXY"] as? [Double], xy.count == 2 {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).press(forDuration: 1.2)
            }
            if let scale = step["pinch"] as? Double { app.pinch(withScale: scale, velocity: scale < 1 ? -1 : 1) }
            // Pinch on a labelled element: {"pinchOn":"Video player","scale":0.4}
            if let label = step["pinchOn"] as? String {
                let scale = step["scale"] as? Double ?? 0.4
                let element = app.descendants(matching: .any)[label].firstMatch
                if element.waitForExistence(timeout: 5) { element.pinch(withScale: scale, velocity: scale < 1 ? -1 : 1) } else { attachText("missing-\(i)", "No element labelled \(label)") }
            }
            if step["home"] != nil { XCUIDevice.shared.press(.home) }
            if step["lock"] != nil { XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton")) }
            if let text = step["type"] as? String { app.typeText(text) }
            if let seconds = step["wait"] as? Double { Thread.sleep(forTimeInterval: seconds) }
            if let name = step["shot"] as? String {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = String(format: "%02d-%@", i, name)
                shot.lifetime = .keepAlways
                add(shot)
            }
            if step["dump"] != nil { attachText(String(format: "%02d-tree", i), app.debugDescription) }
        }
    }

    private func attachText(_ name: String, _ text: String) {
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
