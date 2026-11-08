import XCTest

/// Drives Boxtube on a real iPhone from a list of steps passed in the BOXTUBE_STEPS environment variable
/// (set TEST_RUNNER_BOXTUBE_STEPS when calling xcodebuild). Each step is one of:
///   {"launch":true} {"activate":true} {"tap":"Accessibility label"} {"tapXY":[x,y]} {"swipe":"up|down|left|right"}
///   {"type":"text"} {"wait":seconds} {"shot":"name"} {"dump":true}
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
