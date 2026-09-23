import SpriteKit
import UIKit

/// Preferences, accessibility options and the optional-backend controls.
final class SettingsScene: ListScene {

    override var screenTitle: String { "SETTINGS" }
    override var segments: [String] { ["GAME", "ACCESS", "SERVER"] }
    override var rowHeight: CGFloat { 50 }

    private let settings = Settings.shared
    private var statusToken: UUID?

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        statusToken = OnlineService.shared.observeStatus { [weak self] _ in
            guard self?.selectedSegment == 2 else { return }
            self?.buildContent()
        }

        if LaunchOptions.showsAccountFormForUITesting {
            DispatchQueue.main.async { [weak self] in
                self?.promptForAccount(upgrade: true)
            }
        }
    }

    override func willMove(from view: SKView) {
        if let statusToken { OnlineService.shared.removeObserver(statusToken) }
    }

    override func buildContent() {
        switch selectedSegment {
        case 1: buildAccessibility()
        case 2: buildServer()
        default: buildGame()
        }
    }

    // MARK: - Sections

    private func buildGame() {
        var rows: [SKNode] = []

        rows.append(toggle("Sound effects", isOn: settings.soundEnabled) { [weak self] value in
            self?.settings.soundEnabled = value
            if value { AudioManager.shared.play(.uiTap) }
        })

        rows.append(toggle("Haptics", isOn: settings.hapticsEnabled) { [weak self] value in
            self?.settings.hapticsEnabled = value
            if value { Haptics.shared.buttonTap() }
        })

        rows.append(toggle("Show FPS counter", isOn: settings.showFPS) { [weak self] value in
            self?.settings.showFPS = value
            self?.applyDebugOverlay(value)
        })

        rows.append(actionRow(
            badge: "🗑",
            title: "Reset local progress",
            subtitle: "Clears all on-device progress",
            buttonTitle: "RESET",
            destructive: true
        ) { [weak self] in
            self?.confirmReset()
        })

        rows.append(makeRow(
            badge: "ℹ️",
            title: "Version",
            subtitle: "Flappy Bird for iOS",
            value: AppInfo.version,
            valueColor: Palette.secondaryText
        ))

        setRows(rows)
    }

    private func buildAccessibility() {
        var rows: [SKNode] = []

        rows.append(toggle("High contrast text", isOn: settings.highContrast) { [weak self] value in
            self?.settings.highContrast = value
        })

        rows.append(toggle("Reduce flashing", isOn: settings.reduceFlashing) { [weak self] value in
            self?.settings.reduceFlashing = value
        })

        rows.append(makeRow(
            badge: "🎛",
            title: "Reduce Motion",
            subtitle: "Follows the iOS system setting",
            value: UIAccessibility.isReduceMotionEnabled ? "ON" : "OFF",
            valueColor: UIAccessibility.isReduceMotionEnabled ? Palette.positive : Palette.secondaryText
        ))

        rows.append(makeRow(
            badge: "🧘",
            title: "Zen mode",
            subtitle: "Practise with no game over — pick it on the menu",
            value: "",
            valueColor: Palette.secondaryText
        ))

        setRows(rows)
    }

    private func buildServer() {
        let service = OnlineService.shared
        var rows: [SKNode] = []

        rows.append(makeRow(
            badge: service.status.isOnline ? "🟢" : "⚪️",
            title: service.status.shortDescription,
            subtitle: serverSubtitle(),
            value: "",
            highlighted: true
        ))

        rows.append(toggle("Enable online features", isOn: settings.onlineEnabled) { [weak self] value in
            if value {
                OnlineService.shared.enableOnline()
            } else {
                OnlineService.shared.disableOnline()
            }
            self?.buildContent()
        })

        rows.append(actionRow(
            badge: "🔗",
            title: "Server URL",
            subtitle: settings.backendURLOverride ?? "Auto-detect (localhost:4000)",
            buttonTitle: "EDIT"
        ) { [weak self] in
            self?.promptForServerURL()
        })

        rows.append(actionRow(
            badge: "🔄",
            title: "Reconnect",
            subtitle: "Find server and sign in again",
            buttonTitle: "RUN"
        ) {
            OnlineService.shared.reconnect()
        })

        // Say what is actually happening: "waiting for a server" while connected
        // reads as a bug even when the queue is simply being paced.
        let pending = GameStore.shared.profile.pendingUploads.count
        let pendingDetail: String
        if pending == 0 {
            pendingDetail = "Everything is synced"
        } else if !service.status.isOnline {
            pendingDetail = "\(pending) run(s) waiting for a server"
        } else if service.isRetryingUploads {
            pendingDetail = "\(pending) run(s) left · retrying shortly"
        } else {
            pendingDetail = "\(pending) run(s) uploading…"
        }

        rows.append(actionRow(
            badge: "☁️",
            title: "Pending uploads",
            subtitle: pendingDetail,
            buttonTitle: "SYNC"
        ) {
            OnlineService.shared.flushQueue()
        })

        if service.isSignedIn {
            rows.append(actionRow(
                badge: "👤",
                title: service.username ?? "Signed in",
                subtitle: service.isGuest ? "Claim guest to keep scores" : "Signed in",
                buttonTitle: service.isGuest ? "UPGRADE" : "SIGN OUT"
            ) { [weak self] in
                if service.isGuest {
                    self?.promptForAccount(upgrade: true)
                } else {
                    Task { @MainActor in
                        await OnlineService.shared.signOut()
                        self?.buildContent()
                    }
                }
            })
        } else if service.status.isOnline {
            rows.append(actionRow(
                badge: "👤",
                title: "Create an account",
                subtitle: "Leaderboards and cloud saves",
                buttonTitle: "SIGN IN"
            ) { [weak self] in
                self?.promptForAccount(upgrade: false)
            })
        }

        rows.append(makeRow(
            badge: "📖",
            title: "Backend is optional",
            subtitle: "Everything works without a server",
            value: "",
            valueColor: Palette.secondaryText
        ))

        setRows(rows)
    }

    private func serverSubtitle() -> String {
        if let config = OnlineService.shared.status.config {
            return "\(config.service) \(config.apiVersion) · \(config.capabilities.count) capabilities"
        }
        if case .offline = OnlineService.shared.status {
            return "Start it with `make up`, then tap Reconnect"
        }
        return "Online features are turned off"
    }

    // MARK: - Row builders

    private func toggle(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> SKNode {
        let container = SKNode()
        let row = ToggleRowNode(title: title, isOn: isOn, width: contentWidth - 8, onChange: onChange)
        container.addChild(row)
        return container
    }

    private func actionRow(
        badge: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> SKNode {
        let row = SKNode()

        let background = SKShapeNode(
            rectOf: CGSize(width: contentWidth - 8, height: rowHeight - 6),
            cornerRadius: 9
        )
        background.fillColor = SKColor(white: 1, alpha: 0.05)
        background.strokeColor = .clear
        row.addChild(background)

        let left = -(contentWidth - 8) / 2 + 14

        let badgeLabel = SKLabelNode(fontNamed: Fonts.body)
        badgeLabel.text = badge
        badgeLabel.fontSize = 15
        badgeLabel.horizontalAlignmentMode = .left
        badgeLabel.verticalAlignmentMode = .center
        badgeLabel.position = CGPoint(x: left, y: 0)
        row.addChild(badgeLabel)

        let button = ButtonNode(
            title: buttonTitle,
            size: CGSize(width: 82, height: 32),
            fontSize: 12,
            borderColor: destructive ? Palette.negative : Palette.panelBorder,
            action: action
        )
        button.position = CGPoint(x: (contentWidth - 8) / 2 - 56, y: 0)
        row.addChild(button)

        // The labels and button share a row. Give text the exact space to the
        // left of the button so long server URLs and explanations truncate
        // before the control instead of drawing underneath it.
        let textStart = left + 32
        let buttonLeft = button.position.x - button.size.width / 2
        let textWidth = max(0, buttonLeft - 10 - textStart)

        let titleLabel = SKLabelNode(fontNamed: Fonts.display)
        titleLabel.text = TextFit.truncate(title, toWidth: textWidth, fontNamed: Fonts.display, fontSize: 14)
        titleLabel.fontSize = 14
        titleLabel.fontColor = destructive ? Palette.negative : Palette.primaryText
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: textStart, y: 8)
        row.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(fontNamed: Fonts.body)
        subtitleLabel.text = TextFit.truncate(subtitle, toWidth: textWidth, fontNamed: Fonts.body, fontSize: 10)
        subtitleLabel.fontSize = 10
        subtitleLabel.fontColor = Palette.secondaryText
        subtitleLabel.horizontalAlignmentMode = .left
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position = CGPoint(x: textStart, y: -9)
        row.addChild(subtitleLabel)

        describeRowText(accessibilitySentence(badge, title, subtitle), in: row, leftOf: button)

        return row
    }

    // MARK: - UIKit prompts

    private var presenter: UIViewController? {
        view?.window?.rootViewController
    }

    private func promptForServerURL() {
        guard let presenter else { return }

        let form = ServerURLFormViewController(
            currentURL: settings.backendURLOverride
        ) { [weak self] value in
            Settings.shared.backendURLOverride = value
            OnlineService.shared.reconnect()
            self?.buildContent()
        }
        presentForm(form, from: presenter)
    }

    private func promptForAccount(upgrade: Bool) {
        guard let presenter else { return }

        let form = AccountFormViewController(
            isClaimingGuest: upgrade,
            submit: { action, username, password in
                switch action {
                case .claim:
                    try await OnlineService.shared.upgradeGuest(username: username, password: password)
                case .register:
                    try await OnlineService.shared.register(username: username, password: password)
                case .signIn:
                    try await OnlineService.shared.signIn(username: username, password: password)
                }
            },
            onSuccess: { [weak self] in
                self?.buildContent()
            }
        )
        presentForm(form, from: presenter)
    }

    private func presentForm(_ form: UIViewController, from presenter: UIViewController) {
        guard presenter.presentedViewController == nil else { return }

        let navigation = UINavigationController(rootViewController: form)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        presenter.present(navigation, animated: true)
    }

    private func confirmReset() {
        guard let presenter else { return }

        let alert = UIAlertController(
            title: "Reset local progress?",
            message: "This clears scores, coins, skins and achievements on this device. It cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            GameStore.shared.resetProgress()
            Settings.shared.selectedSkin = .classic
            self?.buildContent()
        })
        presenter.present(alert, animated: true)
    }

    private func applyDebugOverlay(_ enabled: Bool) {
        view?.showsFPS = enabled
        view?.showsNodeCount = enabled
        view?.showsDrawCount = enabled
    }
}
