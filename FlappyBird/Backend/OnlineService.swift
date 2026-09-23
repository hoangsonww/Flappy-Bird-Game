import Foundation
import UIKit

/// Single entry point every scene uses to talk to the optional backend.
///
/// Design rules:
///  - **The game never waits for the network.** Every call is fire-and-forget or
///    explicitly awaited by a screen that can show its own spinner.
///  - **Failure is normal.** When no server is found the game keeps running with
///    local storage only, and queued runs upload later.
///  - **One place owns the state**, so the HUD's online dot and the menu's
///    "Sign in" row never disagree.
@MainActor
final class OnlineService {

    static let shared = OnlineService()

    /// Connection state, mirrored into the UI.
    enum Status: Equatable {
        /// The player turned online features off.
        case disabled
        /// A discovery probe is in flight.
        case searching
        /// No compatible server answered.
        case offline
        /// Connected, with the server's advertised capabilities.
        case online(ServerConfig)

        var isOnline: Bool { if case .online = self { return true } else { return false } }

        var config: ServerConfig? { if case .online(let config) = self { return config } else { return nil } }

        var shortDescription: String {
            switch self {
            case .disabled: return "Offline mode"
            case .searching: return "Looking for server…"
            case .offline: return "No server found"
            case .online: return "Connected"
            }
        }
    }

    private(set) var status: Status = .disabled
    private(set) var client: APIClient?
    private(set) var lastError: String?

    /// Observers are plain closures — SpriteKit scenes are not SwiftUI views.
    private var statusObservers: [UUID: (Status) -> Void] = [:]

    private let store: GameStore
    private let settings: Settings
    private let authStore: AuthStore
    private var bootstrapTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(
        store: GameStore = .shared,
        settings: Settings = .shared,
        authStore: AuthStore = .shared
    ) {
        self.store = store
        self.settings = settings
        self.authStore = authStore
    }

    // MARK: - Observation

    /// Register for status changes. Returns a token used to unsubscribe.
    @discardableResult
    func observeStatus(_ observer: @escaping (Status) -> Void) -> UUID {
        let token = UUID()
        statusObservers[token] = observer
        observer(status)
        return token
    }

    func removeObserver(_ token: UUID) {
        statusObservers.removeValue(forKey: token)
    }

    private func setStatus(_ newStatus: Status) {
        status = newStatus
        statusObservers.values.forEach { $0(newStatus) }
    }

    // MARK: - Session

    var isSignedIn: Bool { authStore.isSignedIn }
    var username: String? { authStore.username }
    var isGuest: Bool { authStore.isGuest }

    /// Discover a server, restore or create a session, then flush queued runs.
    ///
    /// Safe to call on every launch and whenever the app returns to the
    /// foreground; a second call while one is running is ignored.
    func bootstrap() {
        guard bootstrapTask == nil else { return }
        guard settings.onlineEnabled else {
            setStatus(.disabled)
            return
        }

        setStatus(.searching)
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            defer { self.bootstrapTask = nil }

            guard let found = await BackendDiscovery().discover() else {
                Log.sync.info("No compatible backend found — staying offline")
                self.setStatus(.offline)
                return
            }
            Log.sync.info("Connected to \(found.baseURL.absoluteString)")

            let client = APIClient(baseURL: found.baseURL)
            self.client = client
            self.setStatus(.online(found.config))

            // A guest account is enough to start syncing; the player can upgrade later.
            if !self.authStore.isSignedIn, found.config.supports("auth.guest") {
                do {
                    _ = try await client.loginAsGuest(
                        deviceId: self.settings.deviceId,
                        country: Locale.current.region?.identifier
                    )
                } catch {
                    let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    Log.sync.error("Guest sign-in failed: \(message)")
                    self.lastError = message
                }
            }

            self.flushQueue()
            self.pushAchievements()
        }
    }

    /// Drop the session and stop all network activity.
    func signOut() async {
        await client?.logout()
        authStore.clear()
    }

    func disableOnline() {
        settings.onlineEnabled = false
        client = nil
        setStatus(.disabled)
    }

    func enableOnline() {
        settings.onlineEnabled = true
        bootstrap()
    }

    /// Re-run discovery, e.g. after the player edits the server URL.
    func reconnect() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        retryTask?.cancel()
        retryTask = nil
        isRetryingUploads = false
        client = nil
        authStore.clear()
        bootstrap()
    }

    func signIn(username: String, password: String) async throws {
        guard let client else { throw APIError.offline }
        _ = try await client.login(username: username, password: password)
        flushQueue()
        pushAchievements()
    }

    func register(username: String, password: String) async throws {
        guard let client else { throw APIError.offline }
        _ = try await client.register(
            username: username,
            password: password,
            country: Locale.current.region?.identifier
        )
        flushQueue()
        pushAchievements()
    }

    /// Replace the generated guest identity without losing its server-side
    /// scores, achievements or friends.
    func upgradeGuest(username: String, password: String) async throws {
        guard let client else { throw APIError.offline }
        _ = try await client.upgradeGuest(username: username, password: password)
        flushQueue()
        pushAchievements()
    }

    // MARK: - Score submission

    /// Result surfaced on the game-over panel.
    struct SubmissionOutcome {
        var rank: Int?
        var totalPlayers: Int?
        var flagged: Bool
        var queued: Bool
        /// Short, player-facing reason shown on the summary panel when a run did
        /// not reach the server — "no server", "signed out", "timed out"…
        var detail: String?
    }

    /// Submit the most recent run, awaiting only briefly.
    ///
    /// The game-over panel calls this with a short timeout: if the server is slow
    /// the run is left in the queue and the panel says "queued" instead of
    /// blocking the player.
    func submitLatestRun(timeout: TimeInterval = 3.0) async -> SubmissionOutcome {
        guard status.isOnline, let client, authStore.isSignedIn,
              let run = store.profile.pendingUploads.last
        else {
            Log.sync.notice(
                "Skipping upload — online=\(self.status.isOnline) "
                    + "signedIn=\(self.authStore.isSignedIn) "
                    + "client=\(self.client != nil) "
                    + "pending=\(self.store.profile.pendingUploads.count)"
            )
            let reason: String
            if !status.isOnline || client == nil {
                reason = "no server"
            } else if !authStore.isSignedIn {
                reason = "signed out"
            } else {
                reason = "nothing to send"
            }

            return SubmissionOutcome(
                rank: nil,
                totalPlayers: nil,
                flagged: false,
                queued: !store.profile.pendingUploads.isEmpty,
                detail: reason
            )
        }

        let submission = ScoreSubmission(
            run: run,
            clientVersion: AppInfo.version,
            deviceModel: AppInfo.deviceModel
        )

        let work = Task { try await client.submit(submission) }
        let timeoutTask = Task { [work] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            work.cancel()
        }

        defer { timeoutTask.cancel() }

        do {
            let response = try await work.value
            Log.sync.info("Uploaded run score=\(run.score) rank=\(response.rank ?? -1)")
            store.markUploaded([run])
            if run.mode == .daily {
                store.markDailyCompleted(DailyChallengeHelper.todayKey())
                try? await client.submitChallengeEntry(score: run.score)
            }
            return SubmissionOutcome(
                rank: response.rank,
                totalPlayers: response.totalPlayers,
                flagged: response.flagged,
                queued: false,
                detail: nil
            )
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            lastError = message
            Log.sync.error("Upload failed: \(message)")
            // Leave it queued; `flushQueue()` retries in the background.
            return SubmissionOutcome(
                rank: nil,
                totalPlayers: nil,
                flagged: false,
                queued: true,
                detail: String(message.prefix(40))
            )
        }
    }

    /// Upload everything still queued, oldest first.
    ///
    /// Paced deliberately. A backlog uploaded in a tight loop trips the server's
    /// submit rate limit (60/min by default), which returns `429` and stalls the
    /// queue until the app is next foregrounded — while the UI still says
    /// "connected". So: a small gap between runs, a bounded batch, and a
    /// scheduled retry when the server pushes back.
    func flushQueue() {
        guard syncTask == nil, status.isOnline, let client, authStore.isSignedIn else { return }
        let pending = store.profile.pendingUploads
        guard !pending.isEmpty else { return }

        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.syncTask = nil }

            var uploaded: [RunRecord] = []
            var retryNeeded = false

            for run in pending.prefix(Self.flushBatchSize) {
                if Task.isCancelled { break }

                let submission = ScoreSubmission(
                    run: run,
                    clientVersion: AppInfo.version,
                    deviceModel: AppInfo.deviceModel
                )

                do {
                    _ = try await client.submit(submission)
                    uploaded.append(run)
                } catch let error as APIError {
                    if error.isRetryable {
                        // Rate limited or a server blip: stop, keep the rest queued.
                        Log.sync.notice("Flush paused: \(error.errorDescription ?? "retryable error")")
                        self.lastError = error.errorDescription
                        retryNeeded = true
                        break
                    }
                    // A permanent rejection must not block the queue forever.
                    Log.sync.error("Dropping rejected run: \(error.errorDescription ?? "rejected")")
                    uploaded.append(run)
                } catch {
                    retryNeeded = true
                    break
                }

                // Stay comfortably under the submit limit.
                try? await Task.sleep(nanoseconds: UInt64(Self.flushSpacing * 1_000_000_000))
            }

            if !uploaded.isEmpty {
                Log.sync.info("Flushed \(uploaded.count) queued run(s)")
                self.store.markUploaded(uploaded)
            }

            // More to send, or the server asked us to slow down: come back later.
            if retryNeeded || !self.store.profile.pendingUploads.isEmpty {
                self.scheduleFlushRetry()
            } else {
                self.lastError = nil
            }
        }
    }

    /// Runs uploaded per flush, and the gap between them.
    private static let flushBatchSize = 20
    private static let flushSpacing: TimeInterval = 0.25
    /// How long to wait before trying the rest of the backlog.
    private static let flushRetryDelay: TimeInterval = 20

    /// `true` while a backlog is waiting on a scheduled retry — surfaced in Settings.
    private(set) var isRetryingUploads = false

    private func scheduleFlushRetry() {
        guard retryTask == nil else { return }
        isRetryingUploads = true

        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.flushRetryDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.isRetryingUploads = false
            self.flushQueue()
        }
    }

    /// Push local achievement progress. Merge on the server is monotonic.
    func pushAchievements() {
        guard status.isOnline, let client, authStore.isSignedIn else { return }
        let payload = AchievementSystem(store: store).syncPayload()
        guard !payload.isEmpty else { return }

        Task {
            _ = try? await client.syncAchievements(payload)
        }
    }

    // MARK: - Reads

    func leaderboard(
        mode: GameMode?,
        window: String,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> LeaderboardPage {
        guard let client else { throw APIError.offline }
        return try await client.leaderboard(mode: mode, window: window, limit: limit, offset: offset)
    }

    func ownRank(mode: GameMode?, window: String) async -> OwnRankResponse? {
        guard let client, authStore.isSignedIn else { return nil }
        return try? await client.ownRank(mode: mode, window: window)
    }

    /// Today's challenge from the server, or `nil` to fall back to local derivation.
    func todayChallenge() async -> APIDailyChallenge? {
        guard let client else { return nil }
        return try? await client.todayChallenge().challenge
    }
}

/// Build metadata reported with each submitted run.
enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
