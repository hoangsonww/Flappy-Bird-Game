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
        let toggle = try XCTUnwrap(
            app.buttons.allElementsBoundByIndex.first { onOff.contains(($0.value as? String) ?? "") },
            "No on/off toggle on the GAME tab. On screen: \(visibleLabels())"
        )
        let before = (toggle.value as? String) ?? ""
        let after = before == "on" ? "off" : "on"

        tap(element: toggle)
        let flipped = expectation(
            for: NSPredicate(format: "value == %@", after),
            evaluatedWith: toggle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [flipped], timeout: GameUITestCase.uiTimeout), .completed,
            "\"\(toggle.label)\" was \(before) and did not become \(after)"
        )
    }

    func testAccessibilityTabListsItsSwitches() {
        launch(screen: "settings", segment: 1)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(
            labels.contains { $0.contains("Reduce") },
            "The accessibility tab has no reduce-motion row. On screen: \(labels)"
        )
        capture("settings-access")
    }

    func testServerTabExplainsTheOptionalBackend() {
        launch(screen: "settings", segment: 2)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(
            labels.contains { $0.contains("Server URL") || $0.contains("Backend") },
            "The server tab says nothing about the backend. On screen: \(labels)"
        )
        capture("settings-server")
    }

    func testSettingsReturnsToTheMenu() {
        launch(screen: "settings")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }
}
