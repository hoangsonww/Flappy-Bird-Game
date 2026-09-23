import UIKit

enum AccountSubmission {
    case claim
    case register
    case signIn
}

/// The account constraints shared by registration and guest claiming.
///
/// Keeping these checks on-device avoids sending obviously invalid forms and,
/// more importantly, gives the player a useful field-level explanation instead
/// of replacing the entire Settings screen with "Invalid request body".
enum AccountCredentialsValidator {

    static func validationMessage(username: String, password: String) -> String? {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (3...20).contains(username.count) else {
            return "Username must be 3–20 characters."
        }
        guard username.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else {
            return "Use only letters, numbers, and underscores in the username."
        }
        guard (8...128).contains(password.count) else {
            return "Password must be 8–128 characters."
        }
        return nil
    }
}

enum AccountFormErrorMessage {

    static func message(for error: Error) -> String {
        if case APIError.server(let code, let message, _) = error {
            if code == "validation_error" || message.localizedCaseInsensitiveContains("invalid request") {
                return "The server rejected these details. Check the username and password requirements above."
            }
            return message
        }
        return (error as? APIError)?.errorDescription
            ?? error.localizedDescription
    }
}

/// A keyboard-safe account form presented above the SpriteKit view.
///
/// `UIAlertController` text fields are unreliable when layered over an `SKView`
/// on newer iOS runtimes: the alert can render while never accepting keyboard
/// focus. A normal view controller owns real text fields and an explicit focus
/// lifecycle, so typing works with touch, hardware keyboards, and XCUITest.
@MainActor
final class AccountFormViewController: UIViewController, UITextFieldDelegate {

    typealias Submit = @MainActor (AccountSubmission, String, String) async throws -> Void

    private let isClaimingGuest: Bool
    private let submit: Submit
    private let onSuccess: () -> Void

    private let usernameField = SettingsFormStyle.textField(
        placeholder: "Username",
        contentType: .username
    )
    private let passwordField = SettingsFormStyle.textField(
        placeholder: "Password",
        contentType: .password,
        secure: true
    )
    private let errorLabel = SettingsFormStyle.errorLabel()
    private lazy var primaryButton = SettingsFormStyle.button(
        title: isClaimingGuest ? "Claim account" : "Create account",
        primary: true,
        action: UIAction { [weak self] _ in
            self?.submitForm(self?.isClaimingGuest == true ? .claim : .register)
        }
    )
    private lazy var signInButton = SettingsFormStyle.button(
        title: isClaimingGuest ? "Sign in instead" : "Sign in",
        primary: false,
        action: UIAction { [weak self] _ in self?.submitForm(.signIn) }
    )
    private var submissionTask: Task<Void, Never>?

    init(
        isClaimingGuest: Bool,
        submit: @escaping Submit,
        onSuccess: @escaping () -> Void
    ) {
        self.isClaimingGuest = isClaimingGuest
        self.submit = submit
        self.onSuccess = onSuccess
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = isClaimingGuest ? "Claim your account" : "Account"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        usernameField.delegate = self
        passwordField.delegate = self
        usernameField.autocorrectionType = .no
        usernameField.autocapitalizationType = .none
        usernameField.returnKeyType = .next
        passwordField.returnKeyType = .go

        let explanation = SettingsFormStyle.explanationLabel(
            isClaimingGuest
                ? "Choose a username and password. Your guest scores, achievements, and friends stay with this account."
                : "Create an account or sign in to sync scores and appear on the leaderboard."
        )
        let hint = SettingsFormStyle.hintLabel(
            "Username: 3–20 letters, numbers, or underscores\nPassword: at least 8 characters"
        )

        let stack = UIStackView(arrangedSubviews: [
            explanation,
            hint,
            usernameField,
            passwordField,
            errorLabel,
            primaryButton,
            signInButton,
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(22, after: errorLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            usernameField.heightAnchor.constraint(equalToConstant: 52),
            passwordField.heightAnchor.constraint(equalToConstant: 52),
            primaryButton.heightAnchor.constraint(equalToConstant: 52),
            signInButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        submissionTask?.cancel()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameField {
            passwordField.becomeFirstResponder()
        } else {
            submitForm(isClaimingGuest ? .claim : .register)
        }
        return true
    }

    private func submitForm(_ action: AccountSubmission) {
        guard submissionTask == nil else { return }

        let username = (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        if let message = AccountCredentialsValidator.validationMessage(
            username: username,
            password: password
        ) {
            showError(message)
            return
        }

        view.endEditing(true)
        setSubmitting(true)
        submissionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await submit(action, username, password)
                guard !Task.isCancelled else { return }
                onSuccess()
                dismiss(animated: true)
            } catch {
                guard !Task.isCancelled else { return }
                showError(AccountFormErrorMessage.message(for: error))
                setSubmitting(false)
                submissionTask = nil
            }
        }
    }

    private func setSubmitting(_ submitting: Bool) {
        usernameField.isEnabled = !submitting
        passwordField.isEnabled = !submitting
        primaryButton.isEnabled = !submitting
        signInButton.isEnabled = !submitting
        primaryButton.configuration?.showsActivityIndicator = submitting
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Editable backend address with an explicit auto-detect option.
@MainActor
final class ServerURLFormViewController: UIViewController, UITextFieldDelegate {

    private let currentURL: String?
    private let onSave: (String?) -> Void
    private let urlField = SettingsFormStyle.textField(
        placeholder: "http://192.168.1.20:4000",
        contentType: .URL
    )
    private let errorLabel = SettingsFormStyle.errorLabel()

    init(currentURL: String?, onSave: @escaping (String?) -> Void) {
        self.currentURL = currentURL
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Backend server"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        urlField.text = currentURL
        urlField.delegate = self
        urlField.keyboardType = .URL
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.returnKeyType = .done

        let explanation = SettingsFormStyle.explanationLabel(
            "Enter a backend reachable from this device, or use automatic discovery for localhost:4000."
        )
        let save = SettingsFormStyle.button(
            title: "Save and reconnect",
            primary: true,
            action: UIAction { [weak self] _ in self?.saveURL() }
        )
        let automatic = SettingsFormStyle.button(
            title: "Use auto-detect",
            primary: false,
            action: UIAction { [weak self] _ in self?.finish(with: nil) }
        )

        let stack = UIStackView(arrangedSubviews: [explanation, urlField, errorLabel, save, automatic])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(22, after: errorLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            urlField.heightAnchor.constraint(equalToConstant: 52),
            save.heightAnchor.constraint(equalToConstant: 52),
            automatic.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        urlField.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveURL()
        return true
    }

    private func saveURL() {
        let raw = (urlField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            finish(with: nil)
            return
        }
        guard let url = BackendDiscovery.normalise(raw) else {
            errorLabel.text = "Enter a valid HTTP or HTTPS address."
            errorLabel.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
            return
        }
        finish(with: url.absoluteString)
    }

    private func finish(with value: String?) {
        onSave(value)
        dismiss(animated: true)
    }
}

@MainActor
private enum SettingsFormStyle {

    static func textField(
        placeholder: String,
        contentType: UITextContentType,
        secure: Bool = false
    ) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.textContentType = contentType
        field.isSecureTextEntry = secure
        field.borderStyle = .roundedRect
        field.backgroundColor = .secondarySystemGroupedBackground
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.clearButtonMode = .whileEditing
        return field
    }

    static func explanationLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func hintLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func errorLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        label.accessibilityTraits = .staticText
        return label
    }

    static func button(title: String, primary: Bool, action: UIAction) -> UIButton {
        var configuration = primary ? UIButton.Configuration.filled() : .bordered()
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = primary ? .systemGreen : nil
        configuration.baseForegroundColor = primary ? .black : .label
        let button = UIButton(configuration: configuration, primaryAction: action)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }
}
