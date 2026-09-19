import XCTest

@testable import FlappyBird

/// The daily challenge only works if the generator is reproducible.
final class SeededRandomTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var first = SeededRandom(seed: 42)
        var second = SeededRandom(seed: 42)

        let a = (0..<50).map { _ in first.next() }
        let b = (0..<50).map { _ in second.next() }

        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsDiverge() {
        var first = SeededRandom(seed: 1)
        var second = SeededRandom(seed: 2)

        let a = (0..<20).map { _ in first.next() }
        let b = (0..<20).map { _ in second.next() }

        XCTAssertNotEqual(a, b)
    }

    func testZeroSeedDoesNotDegenerate() {
        var generator = SeededRandom(seed: 0)
        let values = Set((0..<32).map { _ in generator.next() })
        XCTAssertEqual(values.count, 32, "A zero seed must not collapse the sequence")
    }

    func testStringSeedIsStable() {
        var first = SeededRandom(stringSeed: "d89338447203ed2f")
        var second = SeededRandom(stringSeed: "d89338447203ed2f")
        XCTAssertEqual(first.next(), second.next())

        var third = SeededRandom(stringSeed: "d89338447203ed2f")
        var other = SeededRandom(stringSeed: "d89338447203ed30")
        XCTAssertNotEqual(third.next(), other.next())
    }

    func testUnitValuesStayInRange() {
        var generator = SeededRandom(seed: 7)
        for _ in 0..<2_000 {
            let value = generator.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testDoubleRangeIsRespected() {
        var generator = SeededRandom(seed: 11)
        for _ in 0..<1_000 {
            let value = generator.nextDouble(in: 120...480)
            XCTAssertGreaterThanOrEqual(value, 120)
            XCTAssertLessThanOrEqual(value, 480)
        }
    }

    func testIntRangeIsInclusiveAndCoversTheSpan() {
        var generator = SeededRandom(seed: 3)
        var seen = Set<Int>()
        for _ in 0..<500 {
            let value = generator.nextInt(in: 1...6)
            XCTAssertTrue((1...6).contains(value))
            seen.insert(value)
        }
        XCTAssertEqual(seen, Set(1...6), "All outcomes should appear over 500 rolls")
    }

    func testIntRangeHandlesSingleValue() {
        var generator = SeededRandom(seed: 5)
        XCTAssertEqual(generator.nextInt(in: 4...4), 4)
    }

    func testChanceApproximatesTheRequestedProbability() {
        var generator = SeededRandom(seed: 99)
        let trials = 20_000
        let hits = (0..<trials).filter { _ in generator.chance(0.25) }.count
        let ratio = Double(hits) / Double(trials)
        XCTAssertEqual(ratio, 0.25, accuracy: 0.02)
    }

    func testNewSeedStringsDiffer() {
        let seeds = Set((0..<50).map { _ in SeededRandom.newSeedString() })
        XCTAssertGreaterThan(seeds.count, 45, "Fresh run seeds should rarely collide")
    }
}
