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
            subtitle: "Scores, coins, skins and achievements",
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
            subtitle: "Re-run discovery and sign in again",
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
                subtitle: service.isGuest ? "Guest account — create one to keep your scores" : "Signed in",
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
                subtitle: "Needed for leaderboards and cloud saves",
                buttonTitle: "SIGN IN"
            ) { [weak self] in
                self?.promptForAccount(upgrade: false)
            })
        }

        rows.append(makeRow(
            badge: "📖",
            title: "Backend is optional",
            subtitle: "The game is fully playable with no server at all",
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

        let titleLabel = SKLabelNode(fontNamed: Fonts.display)
        titleLabel.text = title
        titleLabel.fontSize = 14
        titleLabel.fontColor = destructive ? Palette.negative : Palette.primaryText
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: left + 32, y: 8)
        row.addChild(titleLabel)

        let subtitleLabel = SKLabelNode(fontNamed: Fonts.body)
        subtitleLabel.text = subtitle
        subtitleLabel.fontSize = 10
        subtitleLabel.fontColor = Palette.secondaryText
        subtitleLabel.horizontalAlignmentMode = .left
        subtitleLabel.verticalAlignmentMode = .center
        subtitleLabel.position = CGPoint(x: left + 32, y: -9)
        row.addChild(subtitleLabel)

        let button = ButtonNode(
            title: buttonTitle,
            size: CGSize(width: 82, height: 32),
            fontSize: 12,
            borderColor: destructive ? Palette.negative : Palette.panelBorder,
            action: action
        )
        button.position = CGPoint(x: (contentWidth - 8) / 2 - 56, y: 0)
        row.addChild(button)

        describeRowText(accessibilitySentence(badge, title, subtitle), in: row, leftOf: button)

        return row
    }

    // MARK: - UIKit prompts

    private var presenter: UIViewController? {
        view?.window?.rootViewController
    }

    private func promptForServerURL() {
        guard let presenter else { return }

        let alert = UIAlertController(
            title: "Backend URL",
            message: "Leave empty to auto-detect a server on localhost:4000.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "http://192.168.1.20:4000"
            field.text = Settings.shared.backendURLOverride
            field.keyboardType = .URL
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                Settings.shared.backendURLOverride = nil
            } else if let url = BackendDiscovery.normalise(trimmed) {
                Settings.shared.backendURLOverride = url.absoluteString
            } else {
                self?.showStatus("That does not look like a URL.")
                return
            }
            OnlineService.shared.reconnect()
            self?.buildContent()
        })
        presenter.present(alert, animated: true)
    }

    private func promptForAccount(upgrade: Bool) {
        guard let presenter else { return }

        let alert = UIAlertController(
            title: upgrade ? "Claim your account" : "Sign in or register",
            message: "Usernames are 3–20 characters. Passwords need at least 8.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "username"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addTextField { field in
            field.placeholder = "password"
            field.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        let submit: (Bool) -> UIAlertAction = { [weak self] isRegistration in
            UIAlertAction(title: isRegistration ? "Register" : "Sign in", style: .default) { _ in
                let username = alert.textFields?.first?.text ?? ""
                let password = alert.textFields?.last?.text ?? ""

                Task { @MainActor in
                    do {
                        if isRegistration {
                            try await OnlineService.shared.register(username: username, password: password)
                        } else {
                            try await OnlineService.shared.signIn(username: username, password: password)
                        }
                        self?.buildContent()
                    } catch {
                        let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                        self?.showStatus(message)
                    }
                }
            }
        }

        alert.addAction(submit(true))
        alert.addAction(submit(false))
        presenter.present(alert, animated: true)
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
