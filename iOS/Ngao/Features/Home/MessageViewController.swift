import UIKit

final class MessageViewController: UIViewController {
    private let messageTitle: String
    private let message: String
    private let symbol: String

    init(title: String, message: String, symbol: String) {
        messageTitle = title
        self.message = message
        self.symbol = symbol
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = Theme.danger
        image.contentMode = .scaleAspectFit
        image.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let title = Theme.title(messageTitle)
        title.textAlignment = .center
        let body = Theme.body(message)
        body.textAlignment = .center
        body.accessibilityIdentifier = "message-body"
        let stack = UIStackView.vertical(spacing: 16, [image, title, body])
        view.addSubview(stack)
        stack.pin(to: view.safeAreaLayoutGuide, insets: UIEdgeInsets(top: 120, left: 24, bottom: 16, right: 24))
    }
}
