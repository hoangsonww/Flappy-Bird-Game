import XCTest
@testable import FlappyBird

final class SettingsFormTests: XCTestCase {

    func testAccountCredentialsAcceptDocumentedBoundaries() {
        XCTAssertNil(AccountCredentialsValidator.validationMessage(username: "abc", password: "12345678"))
        XCTAssertNil(AccountCredentialsValidator.validationMessage(
            username: "abcdefghijklmnopqrst",
            password: String(repeating: "p", count: 128)
        ))
        XCTAssertNil(AccountCredentialsValidator.validationMessage(
            username: "  bird_player_7  ",
            password: "safe-password"
        ))
    }

    func testAccountCredentialsRejectUsernameLengthsOutsideThreeToTwenty() {
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(username: "ab", password: "12345678"),
            "Username must be 3–20 characters."
        )
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(
                username: "abcdefghijklmnopqrstu",
                password: "12345678"
            ),
            "Username must be 3–20 characters."
        )
    }

    func testAccountCredentialsRejectUnsupportedUsernameCharacters() {
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(username: "bird-name", password: "12345678"),
            "Use only letters, numbers, and underscores in the username."
        )
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(username: "bird name", password: "12345678"),
            "Use only letters, numbers, and underscores in the username."
        )
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(username: "bïrd", password: "12345678"),
            "Use only letters, numbers, and underscores in the username."
        )
    }

    func testAccountCredentialsRejectPasswordLengthsOutsideEightToOneHundredTwentyEight() {
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(username: "bird", password: "1234567"),
            "Password must be 8–128 characters."
        )
        XCTAssertEqual(
            AccountCredentialsValidator.validationMessage(
                username: "bird",
                password: String(repeating: "p", count: 129)
            ),
            "Password must be 8–128 characters."
        )
    }

    func testAccountFormTurnsGenericValidationFailuresIntoActionableCopy() {
        XCTAssertEqual(
            AccountFormErrorMessage.message(for: APIError.server(
                code: "validation_error",
                message: "Invalid request body",
                status: 400
            )),
            "The server rejected these details. Check the username and password requirements above."
        )
        XCTAssertEqual(
            AccountFormErrorMessage.message(for: APIError.server(
                code: "conflict",
                message: "Username is already taken",
                status: 409
            )),
            "Username is already taken"
        )
    }
}
