import Foundation

/// Typed HTTP client for the companion backend.
///
/// Responsibilities:
///  - build requests against a discovered base URL;
///  - attach the bearer token, refreshing it transparently on a 401;
///  - decode either the success payload or the server's error envelope.
actor APIClient {

    private let baseURL: URL
    private let session: URLSession
    private let authStore: AuthStore
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Guard against two concurrent refreshes racing each other.
    private var refreshTask: Task<Void, Error>?

    init(baseURL: URL, authStore: AuthStore = .shared, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.authStore = authStore

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }

        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    var serverURL: URL { baseURL }

    // MARK: - Auth

    func register(username: String, password: String, country: String?) async throws -> AuthSession {
        let body: [String: Any?] = ["username": username, "password": password, "country": country]
        let session: AuthSession = try await send(.post, "v1/auth/register", body: body, authenticated: false)
        authStore.store(session: session)
        return session
    }

    func login(username: String, password: String) async throws -> AuthSession {
        let body: [String: Any?] = ["username": username, "password": password]
        let session: AuthSession = try await send(.post, "v1/auth/login", body: body, authenticated: false)
        authStore.store(session: session)
        return session
    }

    /// Device-bound account so a player can sync before choosing a username.
    func loginAsGuest(deviceId: String, country: String?) async throws -> AuthSession {
        let body: [String: Any?] = ["deviceId": deviceId, "country": country]
        let session: AuthSession = try await send(.post, "v1/auth/guest", body: body, authenticated: false)
        authStore.store(session: session)
        return session
    }

    func upgradeGuest(username: String, password: String) async throws -> AuthSession {
        let body: [String: Any?] = ["username": username, "password": password]
        let session: AuthSession = try await send(.post, "v1/auth/upgrade", body: body)
        authStore.store(session: session)
        return session
    }

    func logout() async {
        if let refreshToken = authStore.refreshToken {
            let body: [String: Any?] = ["refreshToken": refreshToken]
            _ = try? await sendNoContent(.post, "v1/auth/logout", body: body, authenticated: false)
        }
        authStore.clear()
    }

    // MARK: - Gameplay

    func submit(_ submission: ScoreSubmission) async throws -> SubmitScoreResponse {
        try await send(.post, "v1/scores", encodable: submission)
    }

    func leaderboard(
        mode: GameMode?,
        window: String,
        limit: Int,
        offset: Int
    ) async throws -> LeaderboardPage {
        var query = [
            URLQueryItem(name: "window", value: window),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let mode {
            query.append(URLQueryItem(name: "mode", value: mode.rawValue))
        }
        return try await send(.get, "v1/leaderboard", query: query, authenticated: false)
    }

    func ownRank(mode: GameMode?, window: String, radius: Int = 3) async throws -> OwnRankResponse {
        var query = [
            URLQueryItem(name: "window", value: window),
            URLQueryItem(name: "radius", value: String(radius)),
        ]
        if let mode {
            query.append(URLQueryItem(name: "mode", value: mode.rawValue))
        }
        return try await send(.get, "v1/leaderboard/me", query: query)
    }

    func syncAchievements(_ entries: [[String: Any]]) async throws -> AchievementSyncResponse {
        try await send(.post, "v1/achievements/me/sync", body: ["achievements": entries])
    }

    func todayChallenge() async throws -> DailyChallengeResponse {
        try await send(.get, "v1/challenges/today", authenticated: false)
    }

    func submitChallengeEntry(score: Int) async throws {
        _ = try await sendNoContentAllowingBody(.post, "v1/challenges/today/entries", body: ["score": score])
    }

    // MARK: - Request plumbing

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
        case put = "PUT"
    }

    private func send<T: Decodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any?]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await perform(
            method,
            path,
            query: query,
            bodyData: body.map { try? JSONSerialization.data(withJSONObject: $0.compactMapValues { $0 }) } ?? nil,
            authenticated: authenticated
        )
        return try decode(data)
    }

    private func send<T: Decodable, B: Encodable>(
        _ method: Method,
        _ path: String,
        encodable: B,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await perform(
            method,
            path,
            query: [],
            bodyData: try encoder.encode(encodable),
            authenticated: authenticated
        )
        return try decode(data)
    }

    private func sendNoContent(
        _ method: Method,
        _ path: String,
        body: [String: Any?]? = nil,
        authenticated: Bool = true
    ) async throws {
        _ = try await perform(
            method,
            path,
            query: [],
            bodyData: body.map { try? JSONSerialization.data(withJSONObject: $0.compactMapValues { $0 }) } ?? nil,
            authenticated: authenticated
        )
    }

    private func sendNoContentAllowingBody(
        _ method: Method,
        _ path: String,
        body: [String: Any?]
    ) async throws -> Data {
        try await perform(
            method,
            path,
            query: [],
            bodyData: try? JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }),
            authenticated: true
        )
    }

    private func perform(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        bodyData: Data?,
        authenticated: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if authenticated {
            if !authStore.hasValidAccessToken {
                try await refreshIfPossible()
            }
            guard let token = authStore.accessToken else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .cannotConnectToHost
                ? APIError.offline
                : APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Malformed response")
        }

        if http.statusCode == 401, authenticated, !isRetry {
            // The access token may simply have expired mid-flight.
            try await refreshIfPossible()
            return try await perform(
                method,
                path,
                query: query,
                bodyData: bodyData,
                authenticated: authenticated,
                isRetry: true
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: http.statusCode
                )
            }
            throw APIError.server(
                code: "http_\(http.statusCode)",
                message: "Request failed with status \(http.statusCode)",
                status: http.statusCode
            )
        }

        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        // 204 responses have an empty body; represent that as an empty object.
        if data.isEmpty, let empty = "{}".data(using: .utf8) {
            return try decoder.decode(T.self, from: empty)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Exchange the refresh token for a new pair, coalescing concurrent callers.
    private func refreshIfPossible() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }
        guard let refreshToken = authStore.refreshToken else { throw APIError.unauthorized }

        let task = Task<Void, Error> { [authStore, baseURL, session, decoder] in
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Malformed refresh response")
            }
            guard http.statusCode == 200 else {
                // The refresh token is gone or revoked: the session is over.
                authStore.clear()
                throw APIError.unauthorized
            }
            let session = try decoder.decode(AuthSession.self, from: data)
            authStore.store(session: session)
        }

        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }
}
