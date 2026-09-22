import XCTest
@testable import FlappyBird

/// Skins, time-of-day cycling and font fallbacks.
final class ThemeTests: XCTestCase {

    func testSkinRawValuesMatchTheBackendContract() {
        XCTAssertEqual(
            Set(BirdSkin.allCases.map(\.rawValue)),
            ["classic", "midnight", "ember", "mint", "royal", "glitch", "aurora", "phoenix"]
        )
    }

    func testClassicSkinIsFree() {
        XCTAssertEqual(BirdSkin.classic.price, 0)
        XCTAssertEqual(BirdSkin.classic.blend, 0, "The default skin shows the original art")

        for skin in BirdSkin.allCases where skin != .classic {
            XCTAssertGreaterThan(skin.price, 0, "\(skin) should cost something")
            XCTAssertGreaterThan(skin.blend, 0, "\(skin) should recolour the sprite")
        }
    }

    func testSkinPricesAreDistinct() {
        let prices = BirdSkin.allCases.map(\.price)
        XCTAssertEqual(prices.count, Set(prices).count, "Distinct prices make the shop readable")
    }

    func testTimeOfDayCyclesBackToDay() {
        var current = TimeOfDay.day
        for _ in 0..<TimeOfDay.allCases.count {
            current = current.next
        }
        XCTAssertEqual(current, .day, "The cycle must be closed")
    }

    func testOnlyNightIsDark() {
        for time in TimeOfDay.allCases {
            XCTAssertEqual(time.isDark, time == .night)
            XCTAssertFalse(time.name.isEmpty)
        }
    }

    func testWorldTintStrengthGrowsIntoTheNight() {
        XCTAssertEqual(TimeOfDay.day.worldTintStrength, 0, "Daytime shows the sprites untinted")
        XCTAssertGreaterThan(TimeOfDay.night.worldTintStrength, TimeOfDay.sunset.worldTintStrength)
    }

    func testFontsAlwaysResolveToSomething() {
        XCTAssertFalse(Fonts.display.isEmpty)
        XCTAssertFalse(Fonts.body.isEmpty)
        XCTAssertNotNil(UIFont(name: Fonts.display, size: 12) ?? UIFont.systemFont(ofSize: 12))
    }

    func testWeatherEffectsAreConsistent() {
        XCTAssertEqual(Weather.clear.windForce, 0)
        XCTAssertGreaterThan(Weather.windy.windForce, 0)
        XCTAssertGreaterThan(Weather.rain.downdraft, 0)
        XCTAssertGreaterThan(Weather.fog.fogAlpha, 0)

        for weather in Weather.allCases {
            XCTAssertFalse(weather.displayName.isEmpty)
            XCTAssertFalse(weather.symbol.isEmpty)
        }
    }

    func testWeatherSelectionIsSeededAndFavoursClear() {
        var first = SeededRandom(seed: 77)
        var second = SeededRandom(seed: 77)
        XCTAssertEqual(Weather.random(using: &first), Weather.random(using: &second))

        var generator = SeededRandom(seed: 1)
        let rolls = (0..<1_000).map { _ in Weather.random(using: &generator) }
        let clearShare = Double(rolls.filter { $0 == .clear }.count) / Double(rolls.count)
        XCTAssertGreaterThan(clearShare, 0.5, "Clear weather should stay the common case")
    }
}
