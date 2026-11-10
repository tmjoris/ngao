import NgaoCore
import UIKit

/// Shows one transfer's state and offers only the actions that are safe in that state.
final class TransferStatusViewController: UIViewController {
    private var machine: TransferMachine
    private let outbox: Outbox
    var onDone: (() -> Void)?

    private let badge = StatusBadgeView()
    private let headline = Theme.title("")
    private let detail = Theme.body("")
    private let amount = Theme.amount(.zero)
    private let actionButton = Theme.primaryButton("Done")
    private let secondaryButton = UIButton(type: .system)

    init(machine: TransferMachine, outbox: Outbox) {
        self.machine = machine
        self.outbox = outbox
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        headline.textAlignment = .center
        detail.textAlignment = .center
        amount.textAlignment = .center
        headline.accessibilityIdentifier = "status-headline"
        detail.accessibilityIdentifier = "status-detail"
        actionButton.accessibilityIdentifier = "status-action"
        secondaryButton.accessibilityIdentifier = "status-secondary"
        actionButton.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
        secondaryButton.addAction(UIAction { [weak self] _ in self?.secondaryTapped() }, for: .touchUpInside)
        badge.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let stack = UIStackView.vertical(spacing: 18, [badge, headline, amount, detail, actionButton, secondaryButton])
        view.addSubview(stack)
        stack.pin(to: view.safeAreaLayoutGuide, insets: UIEdgeInsets(top: 48, left: 24, bottom: 16, right: 24))
        render()
    }

    private func render() {
        amount.text = machine.intent.amount.description
        secondaryButton.isHidden = true
        switch machine.state {
        case .confirmed(let receipt):
            badge.show(.success)
            headline.text = "Sent"
            detail.text = "To \(machine.intent.destination.summary)\nRef \(receipt.reference) · charge \(receipt.charge)"
            actionButton.configuration?.title = "Done"
        case .failed(let failure, _):
            badge.show(.failure)
            headline.text = failure.isRetryable ? "Not sent" : "Declined"
            detail.text = failure.message + (failure.isRetryable ? "\nNothing was debited. You can try again." : "")
            actionButton.configuration?.title = failure.isRetryable ? "Try again" : "Done"
        case .unknown:
            badge.show(.pending)
            headline.text = "Confirming with the bank"
            detail.text = "We sent your transfer but did not get an answer. Do not send it again: we are checking whether it went through. You will not be charged twice."
            actionButton.configuration?.title = "Check now"
            secondaryButton.isHidden = false
            secondaryButton.setTitle("Back to accounts", for: .normal)
        case .pending, .submitted:
            badge.show(.pending)
            headline.text = "Sending…"
            detail.text = "To \(machine.intent.destination.summary)"
            actionButton.configuration?.title = "Back to accounts"
        }
    }

    private func primaryTapped() {
        switch machine.state {
        case .failed(let failure, _) where failure.isRetryable:
            run { try await self.outbox.retry(self.machine.intent.id) }
        case .unknown:
            run {
                _ = try await self.outbox.reconcile()
                return await self.outbox.machine(for: self.machine.intent.id) ?? self.machine
            }
        default:
            onDone?()
        }
    }

    private func secondaryTapped() { onDone?() }

    private func run(_ work: @escaping () async throws -> TransferMachine) {
        actionButton.isEnabled = false
        actionButton.configuration?.showsActivityIndicator = true
        Task {
            defer {
                actionButton.isEnabled = true
                actionButton.configuration?.showsActivityIndicator = false
            }
            do {
                machine = try await work()
                render()
            } catch {
                detail.text = error.localizedDescription
            }
        }
    }
}

/// Animated circle with a drawn check, cross or pulsing dots. Pure Core Animation.
final class StatusBadgeView: UIView {
    enum Kind { case success, failure, pending }

    private let circle = CAShapeLayer()
    private let mark = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(circle)
        layer.addSublayer(mark)
        mark.fillColor = UIColor.clear.cgColor
        mark.lineWidth = 6
        mark.lineCap = .round
        mark.lineJoin = .round
        circle.fillColor = UIColor.clear.cgColor
        circle.lineWidth = 6
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 100
        let rect = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        circle.path = UIBezierPath(ovalIn: rect).cgPath
        mark.frame = rect
    }

    func show(_ kind: Kind) {
        mark.removeAllAnimations()
        circle.removeAllAnimations()
        let color: UIColor
        let path = UIBezierPath()
        switch kind {
        case .success:
            color = Theme.green
            path.move(to: CGPoint(x: 28, y: 52))
            path.addLine(to: CGPoint(x: 44, y: 68))
            path.addLine(to: CGPoint(x: 74, y: 34))
        case .failure:
            color = Theme.danger
            path.move(to: CGPoint(x: 34, y: 34)); path.addLine(to: CGPoint(x: 66, y: 66))
            path.move(to: CGPoint(x: 66, y: 34)); path.addLine(to: CGPoint(x: 34, y: 66))
        case .pending:
            color = Theme.gold
            for x in [30, 50, 70] { path.addArc(withCenter: CGPoint(x: x, y: 50), radius: 5, startAngle: 0, endAngle: .pi * 2, clockwise: true) }
        }
        circle.strokeColor = color.cgColor
        mark.strokeColor = color.cgColor
        mark.path = path.cgPath

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.45
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        circle.add(draw, forKey: "draw")

        if kind == .pending {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3
            pulse.toValue = 1
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            mark.add(pulse, forKey: "pulse")
        } else {
            let markDraw = CABasicAnimation(keyPath: "strokeEnd")
            markDraw.fromValue = 0
            markDraw.toValue = 1
            markDraw.duration = 0.35
            markDraw.beginTime = CACurrentMediaTime() + 0.3
            markDraw.fillMode = .backwards
            mark.add(markDraw, forKey: "draw")
            UINotificationFeedbackGenerator().notificationOccurred(kind == .success ? .success : .error)
        }
    }
}
