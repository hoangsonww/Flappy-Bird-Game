import XCTest
@testable import FlappyBird

/// URL handling, discovery candidate ordering and DTO decoding.
final class BackendClientTests: XCTestCase {

    // MARK: - URL normalisation

    func testNormaliseAddsAScheme() {
        XCTAssertEqual(
            BackendDiscovery.normalise("localhost:4000")?.absoluteString,
            "http://localhost:4000"
        )
    }

    func testNormaliseKeepsAnExplicitScheme() {
        XCTAssertEqual(
            BackendDiscovery.normalise("https://play.example.com")?.absoluteString,
            "https://play.example.com"
        )
    }

    func testNormaliseTrimsWhitespaceAndTrailingSlashes() {
        XCTAssertEqual(
            BackendDiscovery.normalise("  http://10.0.0.5:4000///  ")?.absoluteString,
            "http://10.0.0.5:4000"
        )
    }

    func testNormaliseRejectsGarbage() {
        XCTAssertNil(BackendDiscovery.normalise(""))
        XCTAssertNil(BackendDiscovery.normalise("   "))
        XCTAssertNil(BackendDiscovery.normalise("http://"))
    }

    // MARK: - Discovery candidates

    func testLocalhostIsAlwaysACandidate() {
        let discovery = BackendDiscovery(settings: TestSupport.makeSettings(), bundle: .main)
        let urls = discovery.candidates.map(\.absoluteString)

        XCTAssertTrue(urls.contains("http://localhost:4000"))
        XCTAssertTrue(urls.contains("http://127.0.0.1:4000"))
    }

    func testAnOverrideIsProbedFirst() {
        let settings = TestSupport.makeSettings()
        settings.backendURLOverride = "http://192.168.1.50:4000"

        let discovery = BackendDiscovery(settings: settings, bundle: .main)
        XCTAssertEqual(discovery.candidates.first?.absoluteString, "http://192.168.1.50:4000")
    }

    func testCandidatesAreDeduplicated() {
        let settings = TestSupport.makeSettings()
        settings.backendURLOverride = "localhost:4000"

        let discovery = BackendDiscovery(settings: settings, bundle: .main)
        let urls = discovery.candidates.map(\.absoluteString)

        XCTAssertEqual(urls.count, Set(urls).count)
    }

    // MARK: - Decoding

    func testServerConfigDecodesTheProtocolKey() throws {
        // `protocol` is a Swift keyword, so the model maps it explicitly.
        let json = """
        {
          "service": "flappy-bird-backend",
          "apiVersion": "1.0.0",
          "protocol": "flappy-bird/1",
          "environment": "development",
          "capabilities": ["scores.submit", "leaderboard.global"],
          "gameModes": ["classic"],
          "leaderboardWindows": ["all"],
          "birdSkins": ["classic"],
          "requiresSignedRuns": false,
          "limits": { "maxScore": 100000, "leaderboardPageMax": 100 }
        }
        """
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.protocolName, ServerConfig.expectedProtocol)
        XCTAssertTrue(config.isCompatible)
        XCTAssertTrue(config.supports("scores.submit"))
        XCTAssertFalse(config.supports("friends"))
        XCTAssertEqual(config.limits.maxScore, 100_000)
    }

    func testAnUnrelatedServerIsRejected() throws {
        let json = """
        {
          "service": "some-other-api",
          "apiVersion": "3.2.1",
          "protocol": "not-flappy",
          "environment": "production",
          "capabilities": [],
          "gameModes": [],
          "leaderboardWindows": [],
          "birdSkins": [],
          "requiresSignedRuns": false,
          "limits": { "maxScore": 1, "leaderboardPageMax": 1 }
        }
        """
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.isCompatible, "Only a flappy-bird/1 server may be used")
    }

    func testAuthSessionDecodes() throws {
        let json = """
        {
          "user": {
            "id": "2f3a6f1e-0000-4000-8000-000000000000",
            "username": "skyhopper",
            "displayName": "Sky Hopper",
            "country": "US",
            "avatarSkin": "midnight",
            "isGuest": false,
            "email": null,
            "role": "player"
          },
          "tokens": {
            "accessToken": "header.payload.signature",
            "refreshToken": "opaque-refresh-token",
            "tokenType": "Bearer",
            "expiresIn": 900,
            "refreshExpiresAt": "2026-04-18T00:00:00.000Z"
          }
        }
        """
        let session = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))

        XCTAssertEqual(session.user.username, "skyhopper")
        XCTAssertEqual(session.tokens.expiresIn, 900)
        XCTAssertEqual(session.tokens.tokenType, "Bearer")
    }

    func testSubmitResponseDecodesFlaggedRuns() throws {
        let json = """
        {
          "score": {
            "id": "5e1b0000-0000-4000-8000-000000000000",
            "score": 900,
            "mode": "classic",
            "coins": 0,
            "pipesPassed": 900,
            "durationMs": 1000,
            "submittedAt": "2026-03-19T09:00:00.000Z",
            "flagged": true
          },
          "personalBest": false,
          "rank": null,
          "totalPlayers": 0,
          "flagged": true,
          "flagReasons": ["run too short for 900 pipes"],
          "unlockedAchievements": []
        }
        """
        let response = try JSONDecoder().decode(SubmitScoreResponse.self, from: Data(json.utf8))

        XCTAssertTrue(response.flagged)
        XCTAssertNil(response.rank)
        XCTAssertEqual(response.flagReasons.count, 1)
    }

    func testLeaderboardPageDecodes() throws {
        let json = """
        {
          "window": "all",
          "mode": "all",
          "items": [
            {
              "rank": 1,
              "userId": "1",
              "username": "zephyr",
              "displayName": "Zephyr",
              "avatarSkin": "royal",
              "country": "AU",
              "score": 81,
              "mode": "hardcore",
              "achievedAt": "2026-03-19T09:00:00.000Z"
            }
          ],
          "total": 1,
          "limit": 25,
          "offset": 0,
          "hasMore": false
        }
        """
        let page = try JSONDecoder().decode(LeaderboardPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.items.first?.username, "zephyr")
        XCTAssertEqual(page.items.first?.rank, 1)
        XCTAssertFalse(page.hasMore)
    }

    func testOwnRankResponseDecodesRankedAndUnrankedStates() throws {
        let ranked = try JSONDecoder().decode(OwnRankResponse.self, from: Data("""
        {
          "window": "weekly", "rank": 2, "total": 10,
          "entry": {
            "rank": 2, "userId": "u1", "username": "swiftbird",
            "displayName": "Swift Bird", "avatarSkin": "classic", "country": null,
            "score": 54, "mode": "classic", "achievedAt": "2026-09-20T12:00:00.000Z"
          },
          "neighbours": []
        }
        """.utf8))
        XCTAssertEqual(ranked.rank, 2)
        XCTAssertEqual(ranked.entry?.id, "2-u1")

        let unranked = try JSONDecoder().decode(OwnRankResponse.self, from: Data("""
        { "window": "all", "rank": null, "total": 0, "entry": null, "neighbours": [] }
        """.utf8))
        XCTAssertNil(unranked.rank)
        XCTAssertNil(unranked.entry)
        XCTAssertTrue(unranked.neighbours.isEmpty)
    }

    func testAchievementSyncResponseDecodesProgressAndUnlocks() throws {
        let response = try JSONDecoder().decode(AchievementSyncResponse.self, from: Data("""
        {
          "items": [
            { "code": "first_flight", "progress": 1, "unlockedAt": "2026-09-20T12:00:00.000Z" },
            { "code": "century", "progress": 42, "unlockedAt": null }
          ],
          "synced": 2
        }
        """.utf8))
        XCTAssertEqual(response.synced, 2)
        XCTAssertEqual(response.items.first?.code, "first_flight")
        XCTAssertNotNil(response.items.first?.unlockedAt)
        XCTAssertNil(response.items.last?.unlockedAt)
    }

    func testDailyChallengeResponseDecodesEveryModifier() throws {
        let response = try JSONDecoder().decode(DailyChallengeResponse.self, from: Data("""
        {
          "challenge": {
            "date": "2026-09-22", "seed": "daily-seed", "mode": "daily",
            "pipeGap": 148, "gravityScale": 1.05, "speedScale": 1.12,
            "modifier": "windy", "description": "A gusty daily run"
          },
          "rollsOverAt": "2026-09-23T00:00:00.000Z"
        }
        """.utf8))
        XCTAssertEqual(response.challenge.date, "2026-09-22")
        XCTAssertEqual(response.challenge.pipeGap, 148)
        XCTAssertEqual(response.challenge.gravityScale, 1.05, accuracy: 0.001)
        XCTAssertEqual(response.challenge.speedScale, 1.12, accuracy: 0.001)
        XCTAssertEqual(response.challenge.modifier, "windy")
        XCTAssertEqual(response.rollsOverAt, "2026-09-23T00:00:00.000Z")
    }

    func testErrorEnvelopeDecodes() throws {
        let json = """
        { "error": { "code": "validation_failed", "message": "Invalid request body", "requestId": "abc" } }
        """
        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.error.code, "validation_failed")
        XCTAssertEqual(envelope.error.requestId, "abc")
    }

    // MARK: - Error classification

    func testRetryabilityMatchesTheHTTPSemantics() {
        XCTAssertTrue(APIError.offline.isRetryable)
        XCTAssertTrue(APIError.transport("timeout").isRetryable)
        XCTAssertTrue(APIError.server(code: "internal_error", message: "boom", status: 500).isRetryable)
        XCTAssertTrue(APIError.server(code: "rate_limited", message: "slow down", status: 429).isRetryable)

        XCTAssertFalse(APIError.unauthorized.isRetryable)
        XCTAssertFalse(APIError.server(code: "unprocessable", message: "impossible run", status: 422).isRetryable)
    }

    func testEveryErrorHasAPlayerFacingMessage() {
        let errors: [APIError] = [
            .notConfigured,
            .offline,
            .incompatibleServer("wrong protocol"),
            .unauthorized,
            .server(code: "conflict", message: "Username is already taken", status: 409),
            .decoding("bad json"),
            .transport("connection lost"),
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) needs a message")
        }
    }

    // MARK: - Submission mapping

    func testScoreSubmissionMirrorsTheRunRecord() {
        let record = RunRecord(
            score: 42,
            mode: .endless,
            coins: 17,
            pipesPassed: 42,
            durationMs: 61_500,
            maxCombo: 9,
            powerUpsUsed: 2,
            seed: "a1b2c3d4"
        )

        let submission = ScoreSubmission(record: record)
        XCTAssertEqual(submission.mode, "endless")
        XCTAssertEqual(submission.score, 42)
        XCTAssertEqual(submission.durationMs, 61_500)
        XCTAssertEqual(submission.seed, "a1b2c3d4")
    }

    func testScoreSubmissionEncodesTheCompleteBackendContract() throws {
        let record = RunRecord(
            score: 7,
            mode: .hardcore,
            coins: 3,
            pipesPassed: 7,
            durationMs: 12_345,
            maxCombo: 3,
            powerUpsUsed: 0,
            seed: "contract-seed"
        )
        let submission = ScoreSubmission(
            run: record,
            clientVersion: "1.3.0",
            deviceModel: "iPhone",
            signature: "signed"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(submission)) as? [String: Any]
        )

        XCTAssertEqual(object["score"] as? Int, 7)
        XCTAssertEqual(object["mode"] as? String, "hardcore")
        XCTAssertEqual(object["coins"] as? Int, 3)
        XCTAssertEqual(object["pipesPassed"] as? Int, 7)
        XCTAssertEqual(object["durationMs"] as? Int, 12_345)
        XCTAssertEqual(object["maxCombo"] as? Int, 3)
        XCTAssertEqual(object["powerUpsUsed"] as? Int, 0)
        XCTAssertEqual(object["seed"] as? String, "contract-seed")
        XCTAssertEqual(object["clientVersion"] as? String, "1.3.0")
        XCTAssertEqual(object["deviceModel"] as? String, "iPhone")
        XCTAssertEqual(object["signature"] as? String, "signed")
    }
}

private extension ScoreSubmission {
    /// Convenience for tests that do not care about client metadata.
    init(record: RunRecord) {
        self.init(run: record, clientVersion: "test", deviceModel: "test")
    }
}
