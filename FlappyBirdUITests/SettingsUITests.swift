import XCTest

/// Settings: all three tabs, the toggles on each, and the server panel.
final class SettingsUITests: GameUITestCase {

    func testEveryTabOpens() {
        launch(screen: "settings")
        for tab in ["GAME", "ACCESS", "SERVER"] {
            tap(tab)
            XCTAssertTrue(control("‹").exists, "Settings lost its back button on \(tab)")
            capture("settings-\(tab.lowercased())")
        }
    }

    /// A toggle has to change its own value, or the tap did nothing.
    ///
    /// `ToggleNode` publishes its title as the accessibility label and "on"/"off"
    /// as the accessibility value, so the state lives in `value`, not `label`.
    func testToggleFlipsItsValue() throws {
        launch(screen: "settings")
        tap("GAME")

        let onOff = Set(["on", "off"])
        func toggleSnapshot() -> XCUIElementSnapshot? {
            snapshotElements().first { onOff.contains(($0.value as? String) ?? "") }
        }

        waitForLabels("a toggle on the GAME tab") { _ in toggleSnapshot() != nil }
        let toggle = try XCTUnwrap(toggleSnapshot(), "No on/off toggle on the GAME tab")
        let before = (toggle.value as? String) ?? ""
        let after = before == "on" ? "off" : "on"

        tap(snapshot: toggle)

        // Addressed by its label, because the snapshot is a value: the live
        // control is what has to end up reporting the new state.
        let live = app.buttons[toggle.label]
        let flipped = expectation(for: NSPredicate(format: "value == %@", after), evaluatedWith: live)
        XCTAssertEqual(
            XCTWaiter().wait(for: [flipped], timeout: GameUITestCase.uiTimeout),
            .completed,
            "\"\(toggle.label)\" was \(before) and did not become \(after)"
        )
    }

    func testAccessibilityTabListsItsSwitches() {
        launch(screen: "settings", segment: 1)
        waitForLabel(containing: "Reduce")
        capture("settings-access")
    }

    func testEverySettingsTabPublishesActionableControlsInsideTheScreen() {
        launch(screen: "settings")
        for tab in ["GAME", "ACCESS", "SERVER"] {
            tap(tab)
            let controls = snapshotElements().filter { snapshot in
                snapshot.elementType == .button && snapshot.frame.width > 0
            }
            XCTAssertFalse(controls.isEmpty, "Settings tab \(tab) has no controls")
            for control in controls {
                XCTAssertTrue(
                    app.frame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY)),
                    "\(control.label) is off screen on settings tab \(tab)"
                )
            }
        }
    }

    func testServerTabExplainsTheOptionalBackend() {
        launch(screen: "settings", segment: 2)
        waitForLabels("the server tab's backend copy") { labels in
            labels.contains { $0.contains("Server URL") || $0.contains("Backend") }
        }
        capture("settings-server")
    }

    func testAccountSheetAcceptsTypingAndKeepsValidationInline() {
        launch(
            screen: "settings",
            segment: 2,
            extraArguments: ["-show-account-form"]
        )

        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: GameUITestCase.uiTimeout))
        username.tap()
        username.typeText("ab")

        let password = app.secureTextFields["Password"]
        XCTAssertTrue(password.waitForExistence(timeout: GameUITestCase.uiTimeout))
        password.tap()
        password.typeText("1234567")

        XCTAssertEqual(username.value as? String, "ab")
        XCTAssertEqual(password.value as? String, "•••••••")

        app.buttons["Claim account"].tap()
        XCTAssertTrue(app.staticTexts["Username must be 3–20 characters."].waitForExistence(timeout: 2))
        XCTAssertTrue(username.exists, "Validation must stay inside the form instead of replacing Settings")
        capture("settings-account-form-validation")
    }

    func testSettingsReturnsToTheMenu() {
        launch(screen: "settings")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }
}
