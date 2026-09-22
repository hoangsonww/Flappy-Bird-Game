import SpriteKit
import XCTest
@testable import FlappyBird

/// The summary panel sized itself with two hardcoded heights that were roughly
/// 26 points short of what it draws, so the MENU/SHARE row rendered below the
/// card's own bottom edge. These pin the geometry instead.
final class GameOverPanelTests: XCTestCase {

    private func makeSummary(
        rank: Int? = nil,
        queuedForSync: Bool = false,
        isPersonalBest: Bool = false
    ) -> GameOverPanel.Summary {
        GameOverPanel.Summary(
            score: 42,
            best: 58,
            coins: 12,
            pipesPassed: 42,
            maxCombo: 4,
            duration: 51.2,
            mode: .classic,
            medal: .silver,
            isPersonalBest: isPersonalBest,
            cause: .pipe,
            rank: rank,
            totalPlayers: rank == nil ? nil : 128,
            queuedForSync: queuedForSync,
            syncDetail: queuedForSync ? "offline" : nil
        )
    }

    private func makePanel(_ summary: GameOverPanel.Summary, share: Bool = true) -> GameOverPanel {
        GameOverPanel(
            summary: summary,
            width: 320,
            onRetry: {},
            onMenu: {},
            onShare: share ? {} : nil
        )
    }

    /// Every variant, since each adds or drops a stat row.
    private var variants: [(name: String, summary: GameOverPanel.Summary)] {
        [
            ("offline", makeSummary()),
            ("ranked", makeSummary(rank: 7)),
            ("queued", makeSummary(queuedForSync: true)),
            ("personal best", makeSummary(rank: 1, isPersonalBest: true)),
        ]
    }

    func testEveryChildStaysInsideThePanel() {
        for variant in variants {
            let panel = makePanel(variant.summary)
            let bounds = CGRect(
                x: -panel.size.width / 2,
                y: -panel.size.height / 2,
                width: panel.size.width,
                height: panel.size.height
            )

            for child in panel.children where !(child is SKShapeNode) {
                let frame = child.calculateAccumulatedFrame()
                guard frame.width > 0, frame.height > 0 else { continue }
                XCTAssertTrue(
                    bounds.contains(frame),
                    "\(variant.name): a child at \(frame) escapes the panel \(bounds)"
                )
            }
        }
    }

    func testTheLastButtonKeepsItsBottomPadding() {
        for variant in variants {
            let panel = makePanel(variant.summary)
            let buttons = panel.children.compactMap { $0 as? ButtonNode }
            guard let lowest = buttons.min(by: { $0.position.y < $1.position.y }) else {
                XCTFail("\(variant.name): the panel has no buttons")
                continue
            }

            let bottomGap = (lowest.position.y - lowest.size.height / 2) + panel.size.height / 2
            XCTAssertGreaterThanOrEqual(
                bottomGap,
                16,
                "\(variant.name): only \(bottomGap)pt under the last button"
            )
        }
    }

    /// Without a share action the single button spans the full content width.
    func testTheMenuButtonIsCentredWhenThereIsNoShare() {
        let panel = makePanel(makeSummary(), share: false)
        let buttons = panel.children.compactMap { $0 as? ButtonNode }
        XCTAssertEqual(buttons.count, 2, "Expected PLAY AGAIN and MENU only")
        for button in buttons {
            XCTAssertEqual(button.position.x, 0, accuracy: 0.001, "A lone button should be centred")
        }
    }

    func testHeightGrowsWithTheRowCount() {
        let delta = GameOverPanel.height(forRows: 5) - GameOverPanel.height(forRows: 4)
        XCTAssertEqual(delta, 24, accuracy: 0.001)
    }
}
