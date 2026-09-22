import Foundation
import os

/// Unified logging for the parts of the app that can fail silently.
///
/// The optional backend is the main one: discovery, sign-in and score uploads
/// all degrade quietly by design, which is exactly the behaviour that is hard to
/// debug without a trace.
///
/// Read it either way:
///
/// ```bash
/// # Console app / unified logging
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.hoangsonww.flappybird"'
///
/// # Plain stdout (debug builds only)
/// xcrun simctl launch --console-pty booted com.hoangsonww.flappybird
/// ```
struct Log {

    private static let subsystem = "com.hoangsonww.flappybird"

    /// Backend discovery, authentication and score sync.
    static let sync = Log(category: "sync")
    /// Scene lifecycle and run outcomes.
    static let game = Log(category: "game")
    /// Local persistence.
    static let store = Log(category: "store")

    private let category: String
    private let logger: Logger

    private init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: Log.subsystem, category: category)
    }

    func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .public)")
        echo("INFO", text)
    }

    func notice(_ message: @autoclosure () -> String) {
        let text = message()
        logger.notice("\(text, privacy: .public)")
        echo("NOTE", text)
    }

    func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
        echo("ERR ", text)
    }

    /// Debug builds mirror to stderr, which is what `--console-pty` surfaces
    /// (stdout is buffered and frequently never flushed for a UI process).
    private func echo(_ level: String, _ text: String) {
        #if DEBUG
            FileHandle.standardError.write(Data("[\(level)] [\(category)] \(text)\n".utf8))
        #endif
    }
}
