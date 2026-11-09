import XCTest

/// Drives Boxtube on a real iPhone from a list of steps passed in the BOXTUBE_STEPS environment variable
/// (set TEST_RUNNER_BOXTUBE_STEPS when calling xcodebuild). Each step is one of:
///   {"launch":true} {"activate":true} {"tap":"Accessibility label"} {"tapXY":[x,y]} {"swipe":"up|down|left|right"}
///   {"type":"text"} {"wait":seconds} {"shot":"name"} {"dump":true}
///   {"tapPrefix":"More for","index":0,"x":366}
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
                let query = app.descendants(matching: .any).matching(identifier: label)
                if query.firstMatch.waitForExistence(timeout: 5) {
                    // Tap the on-screen match by its centre; menus keep hidden copies of their items.
                    let frames = query.allElementsBoundByIndex.map { $0.frame }.filter { app.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) }
                    if let f = frames.last {
                        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
                    } else { query.firstMatch.tap() }
                } else { attachText("missing-\(i)", "No element labelled \(label)") }
            }
            // The nth on-screen element whose label starts with the text: {"tapPrefix":"More for","index":1}
            if let prefix = step["tapPrefix"] as? String {
                let n = step["index"] as? Int ?? 0
                let all = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).allElementsBoundByIndex
                // On screen by frame, top to bottom (covered screens underneath still count; a negative index counts from the end).
                // "x" keeps only elements whose left edge is at that x, to skip a covered screen's matches.
                let x = step["x"] as? Double
                let visible = all.filter { $0.exists && app.frame.insetBy(dx: 0, dy: 50).contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                    .filter { x == nil || abs($0.frame.minX - x!) < 0.5 }
                    .filter { $0.frame.minY >= (step["minY"] as? Double ?? 0) }
                    .sorted { $0.frame.minY < $1.frame.minY }
                let k = n < 0 ? visible.count + n : n
                if visible.indices.contains(k) {
                    let f = visible[k].frame
                    attachText(String(format: "%02d-tapped", i), "\(visible.map { "\($0.label) \($0.frame)" }.joined(separator: "\n"))\n→ \(k)")
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
                } else { attachText("missing-\(i)", "\(visible.count) visible elements start with \(prefix)") }
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
            // Taps the Home Screen (widgets, icons) rather than the app: {"springTapXY":[x,y]}
            if let xy = step["springTapXY"] as? [Double], xy.count == 2 {
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            }
            if let dir = step["springSwipe"] as? String {
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                dir == "left" ? springboard.swipeLeft() : springboard.swipeRight()
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
