import XCTest

/// Shared plumbing for the UI suite.
///
/// The whole game is SpriteKit, so there is no view hierarchy to query — every
/// control is an `SKNode` that opts into `UIAccessibility`. `ButtonNode` sets
/// `accessibilityLabel` to its title and `.button` traits, which is what makes
/// the queries below resolve.
class GameUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// Long enough for a scene transition plus the fade `PanelNode.present`
    /// runs, short enough that a genuine hang still fails the test quickly.
    static let uiTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // A screenshot of whatever was on screen when a test failed is worth
        // more than the assertion message alone.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .deleteOnSuccess
        shot.name = name
        add(shot)
        app.terminate()
    }

    /// Launch with the tooling switches the capture scripts already use.
    ///
    /// - Parameters:
    ///   - screen: skip the menu and open this screen directly.
    ///   - segment: pre-select a filter chip on a list screen.
    ///   - mode: force a game mode.
    ///   - seedDemoData: fill the profile with a plausible history.
    @discardableResult
    func launch(
        screen: String? = nil,
        segment: Int? = nil,
        mode: String? = nil,
        seedDemoData: Bool = true
    ) -> XCUIApplication {
        var arguments: [String] = ["-ui-testing"]
        if seedDemoData { arguments.append("-seed-demo") }
        if let screen { arguments += ["-screen", screen] }
        if let segment { arguments += ["-segment", String(segment)] }
        if let mode { arguments += ["-mode", mode] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    // MARK: - Queries

    /// The control carrying `label`, whatever element type it is published as.
    ///
    /// SpriteKit's accessibility bridge is not consistent about publishing a
    /// node as a button versus a generic element, so this matches on the label
    /// across every type. It must stay a single lazy query: picking the type up
    /// front resolves against whatever is on screen *now*, which then never
    /// matches a control that appears a moment later.
    func control(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @discardableResult
    func waitFor(_ label: String, timeout: TimeInterval = GameUITestCase.uiTimeout) -> XCUIElement {
        let element = control(label)
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "No accessible control labelled \"\(label)\". On screen: \(visibleLabels().joined(separator: ", "))"
        )
        return element
    }

    func tap(_ label: String, timeout: TimeInterval = GameUITestCase.uiTimeout) {
        tap(element: waitFor(label, timeout: timeout))
    }

    /// Tap the centre of `element`.
    ///
    /// Not `element.tap()`: that first asks whether the element is hittable and,
    /// deciding it is not, tries to scroll it into view. SpriteKit publishes no
    /// scrollable container to service that, so the request fails outright with
    /// `kAXErrorCannotComplete` — on some Xcode versions only, which made it a
    /// green local run and a red CI one. A coordinate tap skips the question and
    /// synthesises a touch at the point, which is all any of these controls need
    /// now that their frames are correct.
    func tap(element: XCUIElement) {
        // A coordinate tap lands wherever the point is, so an element scrolled
        // off the screen would silently tap whatever is there instead. Say so.
        XCTAssertTrue(
            app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)),
            "\"\(element.label)\" is off screen at \(element.frame); scroll to it before tapping"
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Assert a label is gone, which is how a scene transition is confirmed.
    func waitForDisappearance(_ label: String, timeout: TimeInterval = GameUITestCase.uiTimeout) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: control(label))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\"\(label)\" never went away")
    }

    /// Every accessibility label currently published, for failure messages.
    func visibleLabels() -> [String] {
        let buttons = app.buttons.allElementsBoundByIndex.map(\.label)
        let others = app.otherElements.allElementsBoundByIndex.map(\.label)
        return (buttons + others).filter { !$0.isEmpty }
    }

    /// Attach a screenshot under `name` so a full run leaves a visual trail.
    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
    }

    /// Tap the middle of the screen — the game's flap input.
    func flap() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
    }

    /// Go from the menu into a run that is actually playing.
    ///
    /// The HUD exists as soon as the game scene is created, so waiting for the
    /// pause control is not enough — the menu's push transition is still
    /// running, and a tap during it never reaches the scene, which leaves the
    /// bird bobbing in its ready state for the rest of the test.
    func startRun() {
        tap("PLAY")
        waitFor("II")
        Thread.sleep(forTimeInterval: GameUITestCase.sceneTransition)
        flap()
    }

    /// The menu→game push, plus a margin.
    static let sceneTransition: TimeInterval = 0.6
}
