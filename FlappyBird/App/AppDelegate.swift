import UIKit

/// Process lifecycle.
///
/// Everything to do with the window lives in `SceneDelegate`; what is left here
/// is genuinely per-process: seeding, audio, haptics and the first attempt at
/// finding a backend.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AudioManager.shared.stop()
    }
}
