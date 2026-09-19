import XCTest

@testable import FlappyBird

/// Parity with the backend's derivation.
///
/// The expected values below were produced by running
/// `backend/src/domain/challenge.ts` — if either side's algorithm drifts, these
/// tests fail and the daily challenge would silently differ between players.
final class DailyChallengeHelperTests: XCTestCase {

    /// One reference case per interesting branch of the algorithm.
    private struct Reference {
        let date: String
        let seed: String
        let mode: GameMode
        let pipeGap: CGFloat
        let gravityScale: CGFloat
        let speedScale: CGFloat
        let modifier: String
    }

    // A reference table. One case per line is far easier to scan and to diff
    // against the server's output than four wrapped argument lists, so the
    // length limit is waived here and nowhere else.
    // swiftlint:disable line_length
    private let references: [Reference] = [
        Reference(date: "2026-03-19", seed: "d89338447203ed2f", mode: .classic, pipeGap: 110, gravityScale: 1.10, speedScale: 1.20, modifier: "nightfall"),
        Reference(date: "2026-01-01", seed: "36e5d70ff5b682b3", mode: .timeAttack, pipeGap: 160, gravityScale: 0.90, speedScale: 1.00, modifier: "windy"),
        Reference(date: "2026-09-19", seed: "a7bf6b4a6380233f", mode: .hardcore, pipeGap: 130, gravityScale: 1.05, speedScale: 0.90, modifier: "turbo"),
        Reference(date: "2026-12-25", seed: "a3b4923e7a40efae", mode: .hardcore, pipeGap: 170, gravityScale: 1.15, speedScale: 1.15, modifier: "none"),
    ]
    // swiftlint:enable line_length

    func testMatchesTheBackendDerivationExactly() {
        for reference in references {
            let challenge = DailyChallengeHelper.derive(for: reference.date)

            XCTAssertEqual(challenge.seed, reference.seed, "seed drift on \(reference.date)")
            XCTAssertEqual(challenge.mode, reference.mode, "mode drift on \(reference.date)")
            XCTAssertEqual(challenge.pipeGap, reference.pipeGap, "gap drift on \(reference.date)")
            XCTAssertEqual(
                challenge.gravityScale,
                reference.gravityScale,
                accuracy: 0.001,
                "gravity drift on \(reference.date)"
            )
            XCTAssertEqual(
                challenge.speedScale,
                reference.speedScale,
                accuracy: 0.001,
                "speed drift on \(reference.date)"
            )
            XCTAssertEqual(challenge.modifier, reference.modifier, "modifier drift on \(reference.date)")
        }
    }

    func testDerivationIsDeterministic() {
        let first = DailyChallengeHelper.derive(for: "2026-05-05")
        let second = DailyChallengeHelper.derive(for: "2026-05-05")
        XCTAssertEqual(first, second)
    }

    func testDifferentDaysDiffer() {
        XCTAssertNotEqual(
            DailyChallengeHelper.derive(for: "2026-05-05").seed,
            DailyChallengeHelper.derive(for: "2026-05-06").seed
        )
    }

    func testEveryParameterStaysInTheDocumentedRange() {
        for day in 1...31 {
            let challenge = DailyChallengeHelper.derive(for: String(format: "2026-07-%02d", day))
            XCTAssertTrue((110...170).contains(challenge.pipeGap))
            XCTAssertTrue((0.85...1.15).contains(challenge.gravityScale))
            XCTAssertTrue((0.90...1.30).contains(challenge.speedScale))
            XCTAssertFalse(challenge.summary.isEmpty)
        }
    }

    func testTodayKeyIsUTCFormatted() throws {
        let key = DailyChallengeHelper.todayKey(now: Date(timeIntervalSince1970: 1_774_000_000))
        XCTAssertEqual(key.count, 10)
        XCTAssertTrue(key.contains("-"))

        // 2026-03-19T23:30:00Z is still the 19th in UTC even though local time may differ.
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-19T23:30:00Z"))
        let late = DailyChallengeHelper.todayKey(now: instant)
        XCTAssertEqual(late, "2026-03-19")
    }

    func testRemoteChallengeWinsOverLocalDerivation() {
        let remote = APIDailyChallenge(
            date: "2026-04-01",
            seed: "abcdef0123456789",
            mode: "endless",
            pipeGap: 142,
            gravityScale: 1.07,
            speedScale: 1.11,
            modifier: "foggy",
            description: "Server says so."
        )

        let resolved = DailyChallengeHelper.resolve(remote: remote)
        XCTAssertEqual(resolved.seed, "abcdef0123456789")
        XCTAssertEqual(resolved.mode, .endless)
        XCTAssertEqual(resolved.pipeGap, 142)
        XCTAssertEqual(resolved.summary, "Server says so.")
    }

    func testResolveFallsBackToLocalDerivationWhenOffline() {
        let resolved = DailyChallengeHelper.resolve(remote: nil)
        XCTAssertEqual(resolved, DailyChallengeHelper.derive(for: DailyChallengeHelper.todayKey()))
    }

    func testModifiersMapToWeather() {
        XCTAssertEqual(DailyChallengeHelper.weather(for: "windy"), .windy)
        XCTAssertEqual(DailyChallengeHelper.weather(for: "foggy"), .fog)
        XCTAssertNil(DailyChallengeHelper.weather(for: "none"))
        XCTAssertNil(DailyChallengeHelper.weather(for: "turbo"))
    }
}
