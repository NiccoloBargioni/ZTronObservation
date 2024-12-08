import Foundation

/// Use this protocol to define an object that stores references to all the components and handles dispatching notifications between them.
///
/// - Note: The `.mediator` property of `delegate` must be the same exact object for all the components that need to part-take in the notification subsystem.
public protocol Mediator: Sendable {
    
    /// Use this function to store a reference to the component to later use, and perform initial configurations if needed.
    func register(_: any Component, or: OnRegisterConflict)
    
    /// Use this function to checkout a component from the notification system, and notify the components of it as seen fit.
    func unregister(_: any Component, or: OnUnregisterConflict)
    
    /// Use this function to perform the 1-to-many streaming of the notification from one component to others.
    func pushNotification(eventArgs: BroadcastArgs, limitToNeighbours: Bool, completion: (() -> Void)?)
}

public enum OnRegisterConflict: Sendable {
    case ignore
    case replace
}

public enum OnUnregisterConflict: Sendable {
    case ignore
    case fail
}

public enum OnSignalInterestFail: Sendable {
    case ignore
    case fail
}
