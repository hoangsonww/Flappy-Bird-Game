import SpriteKit
import UIKit

/// Application entry point.
///
/// The game is a single `UIWindow` hosting one `SKView`; all navigation happens
/// by presenting scenes. This class only wires up app-lifecycle concerns:
/// starting audio, pausing the game when focus is lost, and giving the optional
/// backend a chance to reconnect and flush queued runs.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Capture tooling may ask for a pre-populated profile.
        LaunchOptions.seedDemoDataIfRequested()

        AudioManager.shared.start()
        Haptics.shared.prepare()

        // Discovery runs in the background; the menu shows the result when ready.
        Task { @MainActor in
            OnlineService.shared.bootstrap()
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Losing focus mid-flight would otherwise mean an unfair death.
        gameViewController?.pauseGameIfNeeded()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AudioManager.shared.stop()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        AudioManager.shared.resumeIfNeeded()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AudioManager.shared.resumeIfNeeded()
        Task { @MainActor in
            // A network may have appeared while the app was in the background.
            OnlineService.shared.bootstrap()
            OnlineService.shared.flushQueue()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AudioManager.shared.stop()
    }

    private var gameViewController: GameViewController? {
        window?.rootViewController as? GameViewController
    }
}
