import UIKit

/// Window lifecycle.
///
/// iOS 13 introduced the `UIScene` lifecycle and iOS 27 stopped tolerating apps
/// that ignore it: an app with no `UIApplicationSceneManifest` now traps at
/// launch with `NoSceneLifecycleAdoption` instead of merely warning. The game
/// still has exactly one window hosting one `SKView`; this is where it is built
/// and where the pause-on-losing-focus rule lives, since those are per-scene
/// events rather than per-process ones.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Losing focus mid-flight would otherwise mean an unfair death.
        gameViewController?.pauseGameIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AudioManager.shared.stop()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AudioManager.shared.resumeIfNeeded()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AudioManager.shared.resumeIfNeeded()
        Task { @MainActor in
            // A network may have appeared while the app was in the background.
            OnlineService.shared.bootstrap()
            OnlineService.shared.flushQueue()
        }
    }

    private var gameViewController: GameViewController? {
        window?.rootViewController as? GameViewController
    }
}
