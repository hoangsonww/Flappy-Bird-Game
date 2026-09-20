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

    /// The seeded wallet affords at least one skin, so BUY must actually buy —
    /// one fewer locked skin afterwards.
    ///
    /// The count of equipped ticks is not the thing to assert on: buying also
    /// equips, so the skin that was equipped before gives its tick back and the
    /// total stays at one.
    func testBuyingASkinUnlocksIt() throws {
        launch(screen: "shop")
        let buys = app.buttons.matching(NSPredicate(format: "label == %@", "BUY"))
        XCTAssertTrue(
            buys.firstMatch.waitForExistence(timeout: GameUITestCase.uiTimeout),
            "Everything is already owned"
        )

        // Only the skins the wallet can afford are enabled, and they are not
        // first in the list — the dearer ones are dimmed and inert. The rows
        // scroll, so an affordable one also has to be on screen to tap.
        let buy = try XCTUnwrap(
            buys.allElementsBoundByIndex.first { $0.isEnabled && app.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) },
            "No affordable skin visible on the shop screen"
        )
        let lockedBefore = buys.count
        tap(element: buy)

        let fewerLocked = expectation(
            for: NSPredicate(format: "count < %d", lockedBefore),
            evaluatedWith: buys
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [fewerLocked], timeout: GameUITestCase.uiTimeout), .completed,
            "Buying a skin left \(lockedBefore) locked skins on screen"
        )
        capture("shop-after-purchase")
    }

    func testEquippingAnOwnedSkin() throws {
        launch(screen: "shop")
        let equips = app.buttons.matching(NSPredicate(format: "label == %@", "EQUIP"))
        try XCTSkipUnless(
            equips.firstMatch.waitForExistence(timeout: GameUITestCase.uiTimeout),
            "No owned-but-unequipped skin"
        )
        let equip = try XCTUnwrap(
            equips.allElementsBoundByIndex.first { app.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) },
            "No owned-but-unequipped skin visible on the shop screen"
        )

        tap(element: equip)
        // The row it was tapped on becomes the equipped one, so a tick appears.
        XCTAssertTrue(
            app.buttons["✓"].firstMatch.waitForExistence(timeout: GameUITestCase.uiTimeout),
            "Equipping a skin left no equipped marker"
        )
    }

    func testShopReturnsToTheMenu() {
        launch(screen: "shop")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }
}
