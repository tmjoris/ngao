import NgaoCore
import UIKit

enum Theme {
    static let green = UIColor(red: 0.0, green: 0.42, blue: 0.31, alpha: 1)
    static let gold = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1)
    static let danger = UIColor.systemRed

    static func title(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .title1)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func body(_ text: String, color: UIColor = .secondaryLabel) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func amount(_ money: Money, style: UIFont.TextStyle = .largeTitle) -> UILabel {
        let label = UILabel()
        label.text = money.description
        label.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .bold)
        return label
    }

    static func primaryButton(_ title: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = green
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        return button
    }

    static func field(_ placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.font = .preferredFont(forTextStyle: .body)
        return field
    }
}

extension UIStackView {
    static func vertical(spacing: CGFloat = 12, _ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}

extension UIView {
    func pin(to guide: UILayoutGuide, insets: UIEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
        ])
    }
}
