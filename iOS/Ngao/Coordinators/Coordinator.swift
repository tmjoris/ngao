import UIKit

/// Navigation lives in coordinators, not view controllers. A screen never knows what comes
/// after it, so flows (login, send money) can be reordered or reused without touching views.
@MainActor
protocol Coordinator: AnyObject {
    var children: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func add(_ child: Coordinator) { children.append(child) }
    func remove(_ child: Coordinator) { children.removeAll { $0 === child } }
}
