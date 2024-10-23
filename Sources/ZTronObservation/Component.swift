import Foundation

/// A protocol that identifies a component that can participate to the notification subsystem defined in ZTronObservation.
/// It is recommended that `id` doesn't change between different instances of the same type, if it is required that only one
/// component of the specified type can participate. In that case, it is appropriate to assign an ID that recalls the role of the component
/// in the system. For instance a `TopbarComponent: Component` could be identified by a `topbar` string.
public protocol Component: Identifiable, Hashable {
    var id: String { get }
    var delegate: (any InteractionsManager)? { get set }
}

public extension Component {
    /// Use this function to resolve state updates of components this component depends upon. Just use delegation as default behavior.
    func pushNotification() {
        self.delegate?.pushNotification(eventArgs: BroadcastArgs(source: self))
    }
}
