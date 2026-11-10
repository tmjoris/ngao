import UIKit

final class LoginViewController: UIViewController, NGPinPadViewDelegate {
    private let viewModel: LoginViewModel
    private let message: String?
    var onAuthenticated: (() -> Void)?

    private let pinPad = NGPinPadView()
    private let statusLabel = Theme.body("", color: .secondaryLabel)
    private let biometricButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var countdown: Timer?

    init(viewModel: LoginViewModel, message: String?) {
        self.viewModel = viewModel
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        bind()
        if let message { statusLabel.text = message }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if viewModel.canOfferBiometrics, message == nil {
            Task { await viewModel.submitWithBiometrics() }
        }
    }

    private func buildLayout() {
        let shield = UIImageView(image: UIImage(systemName: "shield.lefthalf.filled"))
        shield.tintColor = Theme.green
        shield.contentMode = .scaleAspectFit
        shield.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = Theme.title("Enter your PIN")
        title.textAlignment = .center
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "login-status"

        pinPad.delegate = self
        pinPad.accentColor = Theme.green
        pinPad.accessibilityIdentifier = "pin-pad"
        pinPad.shuffleKeys()
        pinPad.heightAnchor.constraint(equalToConstant: pinPad.intrinsicContentSize.height).isActive = true

        var configuration = UIButton.Configuration.plain()
        configuration.title = viewModel.biometricKind == .faceID ? "Unlock with Face ID" : "Unlock with Touch ID"
        configuration.image = UIImage(systemName: viewModel.biometricKind == .faceID ? "faceid" : "touchid")
        configuration.imagePadding = 8
        biometricButton.configuration = configuration
        biometricButton.isHidden = !viewModel.canOfferBiometrics
        biometricButton.addAction(UIAction { [weak self] _ in
            Task { await self?.viewModel.submitWithBiometrics() }
        }, for: .touchUpInside)

        spinner.hidesWhenStopped = true
        let stack = UIStackView.vertical(spacing: 20, [shield, title, statusLabel, spinner, pinPad, biometricButton])
        view.addSubview(stack)
        stack.pin(to: view.safeAreaLayoutGuide, insets: UIEdgeInsets(top: 60, left: 24, bottom: 16, right: 24))
    }

    private func bind() {
        viewModel.onChange = { [weak self] state in self?.render(state) }
        render(viewModel.state)
    }

    private func render(_ state: LoginViewModel.State) {
        countdown?.invalidate()
        switch state {
        case .idle:
            spinner.stopAnimating()
            pinPad.isEnabled = true
        case .checking:
            spinner.startAnimating()
            statusLabel.text = ""
            pinPad.isEnabled = false
        case .lockedFor(let seconds):
            spinner.stopAnimating()
            pinPad.isEnabled = false
            statusLabel.textColor = Theme.danger
            statusLabel.text = "Too many attempts. Try again in \(seconds) s."
            countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.viewModel.refreshLockState() }
            }
        case .hardLocked:
            spinner.stopAnimating()
            pinPad.isEnabled = false
            statusLabel.textColor = Theme.danger
            statusLabel.text = "Your PIN is locked. Call 0703 027 000 to unlock it."
        case .error(let text):
            spinner.stopAnimating()
            statusLabel.textColor = Theme.danger
            statusLabel.text = text
            pinPad.clear(animated: true, rejected: true)
        case .authenticated:
            spinner.stopAnimating()
            onAuthenticated?()
        }
    }

    // MARK: - NGPinPadViewDelegate

    func pinPadView(_ pad: NGPinPadView, didCompletePIN pin: String) {
        Task { await viewModel.submit(pin: pin) }
    }
}
