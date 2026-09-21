import SpriteKit
import UIKit

/// Hosts the `SKView` and presents the first scene.
///
/// The original project loaded `GameScene.sks` through `NSKeyedUnarchiver`, which
/// silently crashed whenever the archive and the class layout drifted apart.
/// Scenes are now constructed in code and sized to the view, so the game works on
/// every device and orientation without an archived layout to keep in sync.
final class GameViewController: UIViewController {

    private var skView: SKView {
        // `loadView` guarantees this, but the controller must not crash if it is
        // ever hosted differently.
        view as? SKView ?? {
            let created = SKView(frame: view.bounds)
            view = created
            return created
        }()
    }

    /// The root view *is* the `SKView`.
    ///
    /// This used to come from `Main.storyboard`, which set the root view's class
    /// and nothing else. Building it here lets UIKit size it from the scene it is
    /// placed in, rather than from `UIScreen.main`.
    override func loadView() {
        view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let view = skView
        view.ignoresSiblingOrder = true
        view.showsFPS = Settings.shared.showFPS
        view.showsNodeCount = Settings.shared.showFPS
        view.showsDrawCount = Settings.shared.showFPS
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Present once the view has its final size, so scenes lay out correctly
        // on every device including landscape iPads.
        guard skView.scene == nil, view.bounds.width > 0 else { return }
        presentMenu()
    }

    private func presentMenu() {
        let scene = Self.makeInitialScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    /// Honour `-screen <name>` so capture tooling can open any screen directly.
    static func makeInitialScene(size: CGSize) -> SKScene {
        switch LaunchOptions.initialScreen {
        case .game:
            let scene = GameScene(size: size)
            scene.mode = LaunchOptions.forcedMode ?? Settings.shared.selectedMode
            return scene
        case .leaderboard: return LeaderboardScene(size: size)
        case .achievements: return AchievementsScene(size: size)
        case .shop: return ShopScene(size: size)
        case .stats: return StatsScene(size: size)
        case .settings: return SettingsScene(size: size)
        case .menu, .none: return MenuScene(size: size)
        }
    }

    /// Pause an in-progress run — called from the app delegate.
    func pauseGameIfNeeded() {
        (skView.scene as? GameScene)?.pauseForBackground()
    }

    override var shouldAutorotate: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
    }

    override var prefersStatusBarHidden: Bool { true }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
