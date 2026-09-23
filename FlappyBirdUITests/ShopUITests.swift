import XCTest

/// Buying and equipping a skin, and what happens when the wallet is empty.
final class ShopUITests: GameUITestCase {

    func testShopListsSkinsWithActions() {
        launch(screen: "shop")
        XCTAssertTrue(waitFor("‹").exists)
        waitForLabels("a purchase or equip action") { labels in
            labels.contains { ["BUY", "EQUIP", "✓"].contains($0) }
        }
        capture("shop")
    }

    func testUnaffordablePurchasesAreExposedAsDisabled() {
        launch(screen: "shop")
        waitForLabel(containing: "BUY")
        let buyActions = snapshotElements().filter { $0.label == "BUY" }
        XCTAssertFalse(buyActions.isEmpty)
        XCTAssertTrue(buyActions.contains { !$0.isEnabled }, "Every skin was buyable; unaffordable actions should be disabled")
        XCTAssertTrue(buyActions.contains { $0.isEnabled }, "Seeded wallet should afford at least one skin")
    }

    /// The seeded wallet affords at least one skin, so BUY must actually buy —
    /// one fewer locked skin afterwards.
    ///
    /// The count of equipped ticks is not the thing to assert on: buying also
    /// equips, so the skin that was equipped before gives its tick back and the
    /// total stays at one.
    func testBuyingASkinUnlocksIt() throws {
        launch(screen: "shop")
        waitForLabel(containing: "BUY")

        // Only the skins the wallet can afford are enabled, and they are not
        // first in the list — the dearer ones are dimmed and inert. The rows
        // scroll, so an affordable one also has to be on screen to tap.
        let lockedBefore = actionCount("BUY")
        let buy = try XCTUnwrap(
            snapshotElements().first { element in
                element.label == "BUY" && element.isEnabled
                    && app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
            },
            "No affordable skin visible on the shop screen"
        )
        tap(snapshot: buy)

        waitForLabels("one fewer locked skin") { _ in actionCount("BUY") < lockedBefore }
        capture("shop-after-purchase")
    }

    func testEquippingAnOwnedSkin() throws {
        launch(screen: "shop")
        try XCTSkipUnless(
            app.buttons["EQUIP"].firstMatch.waitForExistence(timeout: GameUITestCase.uiTimeout),
            "No owned-but-unequipped skin"
        )
        let equip = try XCTUnwrap(
            snapshotElements().first { element in
                element.label == "EQUIP"
                    && app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
            },
            "No owned-but-unequipped skin visible on the shop screen"
        )

        tap(snapshot: equip)
        // The row it was tapped on becomes the equipped one, so a tick appears.
        XCTAssertTrue(
            app.buttons["✓"].firstMatch.waitForExistence(timeout: GameUITestCase.uiTimeout),
            "Equipping a skin left no equipped marker"
        )
    }

    /// How many rows currently offer `action`, read atomically.
    private func actionCount(_ action: String) -> Int {
        snapshotElements().filter { $0.label == action }.count
    }

    func testShopReturnsToTheMenu() {
        launch(screen: "shop")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }
}
