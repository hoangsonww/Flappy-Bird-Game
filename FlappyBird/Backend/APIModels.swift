import Foundation

// MARK: - Discovery

/// Response of `GET /v1/meta/config`.
///
/// `protocolName` must equal `flappy-bird/1` before the game trusts a server.
struct ServerConfig: Codable, Equatable {
    let service: String
    let apiVersion: String
    let protocolName: String
    let environment: String
    let capabilities: [String]
    let gameModes: [String]
    let leaderboardWindows: [String]
    let birdSkins: [String]
    let requiresSignedRuns: Bool
    let limits: Limits

    struct Limits: Codable, Equatable {
        let maxScore: Int
        let leaderboardPageMax: Int
    }

    enum CodingKeys: String, CodingKey {
        case service, apiVersion, environment, capabilities, gameModes
        case leaderboardWindows, birdSkins, requiresSignedRuns, limits
        case protocolName = "protocol"
    }

    /// The handshake value that identifies a compatible server.
    static let expectedProtocol = "flappy-bird/1"

    var isCompatible: Bool { protocolName == ServerConfig.expectedProtocol }

    func supports(_ capability: String) -> Bool { capabilities.contains(capability) }
}

// MARK: - Auth

struct APIUser: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let country: String?
    let avatarSkin: String
    let isGuest: Bool
    let email: String?
    let role: String?
}

struct TokenPair: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshExpiresAt: String
}

struct AuthSession: Codable, Equatable {
    let user: APIUser
    let tokens: TokenPair
}

// MARK: - Scores

/// Request body for `POST /v1/scores`.
struct ScoreSubmission: Codable {
    let score: Int
    let mode: String
    let coins: Int
    let pipesPassed: Int
    let durationMs: Int
    let maxCombo: Int
    let powerUpsUsed: Int
    let seed: String
    let clientVersion: String?
    let deviceModel: String?
    let signature: String?

    init(run: RunRecord, clientVersion: String?, deviceModel: String?, signature: String? = nil) {
        self.score = run.score
        self.mode = run.mode.rawValue
        self.coins = run.coins
        self.pipesPassed = run.pipesPassed
        self.durationMs = run.durationMs
        self.maxCombo = run.maxCombo
        self.powerUpsUsed = run.powerUpsUsed
        self.seed = run.seed
        self.clientVersion = clientVersion
        self.deviceModel = deviceModel
        self.signature = signature
    }
}

struct APIScore: Codable, Equatable {
    let id: String
    let score: Int
    let mode: String
    let coins: Int
    let pipesPassed: Int
    let durationMs: Int
    let submittedAt: String
    let flagged: Bool
}

struct SubmitScoreResponse: Codable {
    let score: APIScore
    let personalBest: Bool
    let rank: Int?
    let totalPlayers: Int
    let flagged: Bool
    let flagReasons: [String]
    let unlockedAchievements: [APIUserAchievement]
}

// MARK: - Leaderboards

struct LeaderboardEntry: Codable, Equatable, Identifiable {
    let rank: Int
    let userId: String
    let username: String
    let displayName: String
    let avatarSkin: String
    let country: String?
    let score: Int
    let mode: String
    let achievedAt: String

    var id: String { "\(rank)-\(userId)" }
}

struct LeaderboardPage: Codable {
    let window: String
    let mode: String
    let items: [LeaderboardEntry]
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct OwnRankResponse: Codable {
    let window: String
    let rank: Int?
    let total: Int
    let entry: LeaderboardEntry?
    let neighbours: [LeaderboardEntry]
}

// MARK: - Achievements

struct APIUserAchievement: Codable, Equatable {
    let code: String
    let progress: Int
    let unlockedAt: String?
}

struct AchievementSyncResponse: Codable {
    let items: [APIUserAchievement]
    let synced: Int
}

// MARK: - Challenges

struct APIDailyChallenge: Codable, Equatable {
    let date: String
    let seed: String
    let mode: String
    let pipeGap: Int
    let gravityScale: Double
    let speedScale: Double
    let modifier: String
    let description: String
}

struct DailyChallengeResponse: Codable {
    let challenge: APIDailyChallenge
    let rollsOverAt: String?
}

// MARK: - Errors

/// The server's error envelope.
struct APIErrorEnvelope: Codable {
    struct Payload: Codable {
        let code: String
        let message: String
        let requestId: String?
    }
    let error: Payload
}

/// Every failure the client can surface.
enum APIError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case incompatibleServer(String)
    case unauthorized
    case server(code: String, message: String, status: Int)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No server configured."
        case .offline:
            return "No server reachable — playing offline."
        case .incompatibleServer(let detail):
            return "That server is not a Flappy Bird backend (\(detail))."
        case .unauthorized:
            return "Please sign in again."
        case .server(_, let message, _):
            return message
        case .decoding(let detail):
            return "Unexpected response from server (\(detail))."
        case .transport(let detail):
            return detail
        }
    }

    /// `true` when retrying later could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .offline, .transport:
            return true
        case .server(_, _, let status):
            return status >= 500 || status == 429
        default:
            return false
        }
    }
}
