import XCTest

@testable import FlappyBird

/// Session storage.
///
/// The Keychain is not guaranteed to be writable (unsigned builds and some
/// simulator configurations reject `SecItemAdd`), and a silent failure there
/// used to leave the app looking connected while never uploading anything.
/// These tests pin the contract: a stored session is always usable in-process.
final class AuthStoreTests: XCTestCase {

    private var store: AuthStore!

    override func setUp() {
        super.setUp()
        store = AuthStore(defaults: TestSupport.isolatedDefaults())
        store.clear()
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    private func makeSession(username: String = "tester", isGuest: Bool = true) -> AuthSession {
        AuthSession(
            user: APIUser(
                id: UUID().uuidString,
                username: username,
                displayName: username,
                country: "US",
                avatarSkin: "classic",
                isGuest: isGuest,
                email: nil,
                role: "player"
            ),
            tokens: TokenPair(
                accessToken: "access-token-value",
                refreshToken: "refresh-token-value",
                tokenType: "Bearer",
                expiresIn: 900,
                refreshExpiresAt: "2026-12-31T00:00:00.000Z"
            )
        )
    }

    func testStartsSignedOut() {
        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.username)
    }

    func testStoringASessionMakesItUsableRegardlessOfKeychainAvailability() {
        store.store(session: makeSession(username: "skyhopper", isGuest: false))

        XCTAssertTrue(store.isSignedIn, "A stored session must always count as signed in")
        XCTAssertEqual(store.accessToken, "access-token-value")
        XCTAssertEqual(store.refreshToken, "refresh-token-value")
        XCTAssertEqual(store.username, "skyhopper")
        XCTAssertFalse(store.isGuest)
    }

    func testGuestFlagIsRemembered() {
        store.store(session: makeSession(isGuest: true))
        XCTAssertTrue(store.isGuest)
    }

    func testAccessTokenValidityTracksExpiry() {
        XCTAssertFalse(store.hasValidAccessToken, "No token yet")
        store.store(session: makeSession())
        XCTAssertTrue(store.hasValidAccessToken, "A 900s token is valid immediately after storing")
    }

    func testRotatingTokensReplacesBoth() {
        store.store(session: makeSession())
        store.updateTokens(
            TokenPair(
                accessToken: "rotated-access",
                refreshToken: "rotated-refresh",
                tokenType: "Bearer",
                expiresIn: 900,
                refreshExpiresAt: "2026-12-31T00:00:00.000Z"
            )
        )

        XCTAssertEqual(store.accessToken, "rotated-access")
        XCTAssertEqual(store.refreshToken, "rotated-refresh")
    }

    func testClearRemovesEverything() {
        store.store(session: makeSession())
        store.clear()

        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.refreshToken)
        XCTAssertNil(store.username)
    }
}
