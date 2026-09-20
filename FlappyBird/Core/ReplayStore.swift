import Foundation

/// Local storage for recorded runs.
///
/// Kept out of `PlayerProfile` on purpose. The profile is encoded on every coin
/// and every run, and it is what the backend sync serialises; replays are far
/// larger than everything else in it put together and the server has no use for
/// them, so they live under their own key with their own cap.
final class ReplayStore {

    static let shared = ReplayStore(defaults: .standard)

    /// How many recordings are kept. Oldest are dropped first.
    static let limit = 10

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Newest first.
    private(set) var replays: [Replay]

    init(defaults: UserDefaults, storageKey: String = "player.replays.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([Replay].self, from: data) {
            replays = decoded
        } else {
            replays = []
        }
    }

    /// Store a recording, keeping the newest `limit`.
    func save(_ replay: Replay) {
        guard replay.isPlayable else { return }
        replays.removeAll { $0.id == replay.id }
        replays.insert(replay, at: 0)
        if replays.count > ReplayStore.limit {
            replays.removeSubrange(ReplayStore.limit...)
        }
        persist()
    }

    func replay(with id: UUID) -> Replay? {
        replays.first { $0.id == id }
    }

    func delete(id: UUID) {
        replays.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        replays.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(replays) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
