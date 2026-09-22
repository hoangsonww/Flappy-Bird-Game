import Foundation
import Security

/// Keychain-backed storage for the refresh token.
///
/// The access token is deliberately kept in memory only: it is short-lived and
/// re-minted from the refresh token, so there is no reason to persist it.
final class AuthStore {

    static let shared = AuthStore()

    private let service = "com.hoangsonww.flappybird.auth"
    private let refreshTokenAccount = "refreshToken"
    private let usernameKey = "auth.username"
    private let userIdKey = "auth.userId"
    private let isGuestKey = "auth.isGuest"

    private let defaults: UserDefaults

    /// In-memory only.
    private(set) var accessToken: String?
    private(set) var accessTokenExpiry: Date?

    /// Fallback when the Keychain is unavailable.
    ///
    /// Simulators and unsigned builds can refuse `SecItemAdd`. Without a fallback
    /// the app would look signed in yet never upload anything, because every
    /// gate checks `isSignedIn`. Keeping the token in memory restores the whole
    /// flow for the lifetime of the process; the next launch simply re-creates
    /// the guest session from the device id, which is idempotent server-side.
    private var inMemoryRefreshToken: String?
    /// `true` once a Keychain write has been rejected — surfaced in Settings.
    private(set) var isUsingEphemeralSession = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Session state

    var username: String? { defaults.string(forKey: usernameKey) }
    var userId: String? { defaults.string(forKey: userIdKey) }
    var isGuest: Bool { defaults.bool(forKey: isGuestKey) }

    /// A usable session exists — persisted or in-memory.
    var isSignedIn: Bool { refreshToken != nil || accessToken != nil }

    /// `true` when the cached access token is still usable (with 30s of slack).
    var hasValidAccessToken: Bool {
        guard accessToken != nil, let expiry = accessTokenExpiry else { return false }
        return expiry.timeIntervalSinceNow > 30
    }

    func store(session: AuthSession) {
        accessToken = session.tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(session.tokens.expiresIn))
        setRefreshToken(session.tokens.refreshToken)
        defaults.set(session.user.username, forKey: usernameKey)
        defaults.set(session.user.id, forKey: userIdKey)
        defaults.set(session.user.isGuest, forKey: isGuestKey)
    }

    func updateTokens(_ tokens: TokenPair) {
        accessToken = tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        setRefreshToken(tokens.refreshToken)
    }

    func clear() {
        accessToken = nil
        accessTokenExpiry = nil
        inMemoryRefreshToken = nil
        deleteRefreshToken()
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: isGuestKey)
    }

    // MARK: - Keychain

    var refreshToken: String? {
        keychainRefreshToken ?? inMemoryRefreshToken
    }

    private var keychainRefreshToken: String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    private func setRefreshToken(_ token: String) {
        inMemoryRefreshToken = token

        let data = Data(token.utf8)
        var query = baseQuery()
        let status: OSStatus

        if keychainRefreshToken != nil {
            let attributes: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            query[kSecValueData as String] = data
            // The token is only needed while the app runs, after first unlock.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(query as CFDictionary, nil)
        }

        isUsingEphemeralSession = status != errSecSuccess
    }

    private func deleteRefreshToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: refreshTokenAccount,
        ]
    }
}
