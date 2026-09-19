import Foundation

/// Finds a companion backend without asking the player to configure anything.
///
/// Candidates are probed in priority order and the first compatible server wins:
///
/// 1. an explicit URL typed into Settings (`Settings.backendURLOverride`);
/// 2. `FlappyBackendURL` in `Info.plist` — how a fork ships a default server;
/// 3. `http://localhost:4000` — the simulator shares the Mac's loopback;
/// 4. `http://127.0.0.1:4000`.
///
/// A server is only accepted when `GET /v1/meta/config` returns
/// `protocol == "flappy-bird/1"`, so pointing the game at an unrelated service
/// fails cleanly instead of producing confusing errors later.
struct BackendDiscovery {

    /// Per-candidate probe timeout. Short, because this runs during launch.
    static let probeTimeout: TimeInterval = 1.8

    struct Result: Equatable {
        let baseURL: URL
        let config: ServerConfig
    }

    private let session: URLSession
    private let settings: Settings
    private let bundle: Bundle

    init(settings: Settings = .shared, bundle: Bundle = .main, session: URLSession? = nil) {
        self.settings = settings
        self.bundle = bundle

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = BackendDiscovery.probeTimeout
            configuration.timeoutIntervalForResource = BackendDiscovery.probeTimeout * 2
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Candidate base URLs, in the order they should be tried.
    var candidates: [URL] {
        var raw: [String] = []

        if let override = settings.backendURLOverride {
            raw.append(override)
        }
        if let configured = bundle.object(forInfoDictionaryKey: "FlappyBackendURL") as? String,
           !configured.isEmpty {
            raw.append(configured)
        }
        raw.append("http://localhost:4000")
        raw.append("http://127.0.0.1:4000")

        var seen = Set<String>()
        return raw.compactMap { BackendDiscovery.normalise($0) }
            .filter { seen.insert($0.absoluteString).inserted }
    }

    /// Normalise user input into a usable base URL.
    ///
    /// Accepts `localhost:4000`, `http://host`, trailing slashes and stray
    /// whitespace — all things a person actually types.
    static func normalise(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = "http://\(text)"
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    /// Probe every candidate and return the first compatible server.
    func discover() async -> Result? {
        guard settings.onlineEnabled else { return nil }

        for candidate in candidates {
            if let config = await probe(candidate) {
                return Result(baseURL: candidate, config: config)
            }
        }
        return nil
    }

    /// Check one base URL. Returns `nil` for anything that is not a compatible server.
    func probe(_ baseURL: URL) async -> ServerConfig? {
        let url = baseURL.appendingPathComponent("v1/meta/config")
        var request = URLRequest(url: url)
        request.timeoutInterval = BackendDiscovery.probeTimeout
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let config = try JSONDecoder().decode(ServerConfig.self, from: data)
            return config.isCompatible ? config : nil
        } catch {
            return nil
        }
    }
}
