import Foundation

/// A protocol identifying a class whose responsibility is to manage updates of state of its owner, according to the state changes of observables this component depends upon.
/// A class implementing this protocol could (should?) keep track of the last seen state of other components and update its owners' state accordingly.
public protocol InteractionsManager {
    associatedtype C: Component
    associatedtype M: Mediator
    
    var owner: C? { get }
    var mediator: M? { get }
    
    /// Allows a class implementing this protocol to handle state changes of components that `owner` depends upon.
    ///
    /// - Note: Avoid calling on `owner` (directly or not), operations that use `delegate?.pushNotification()` inside the body of this method.
    /// Only doing so will guarantee a redundant-updates-free environment.
    ///
    /// - Note: `owner` can only be updated via its public interface.
    func notify(args: BroadcastArgs)
    
    
    /// Use this method to do preliminary operations that are required to integrate `owner` in the notification subsystem, such as configuring oneself according
    /// to the current state of other components.
    func setup()
    
    
    /// Use this method to reset the part of state that depends on a component `owner` depends upon when it unregisters from the notification subsystem.
    func willCheckout(args: BroadcastArgs)
    
    
    /// Uses `mediator` to stream the notification to the other dependent components.
    func pushNotification(eventArgs: BroadcastArgs)
    
    
    /// Use this method to detach `owner` from the notification system.
    func detach()
}

public extension InteractionsManager {
    func pushNotification(eventArgs: BroadcastArgs) {
        self.mediator?.pushNotification(eventArgs: eventArgs)
    }
    
    func detach() {
        guard let owner = self.owner else { return }
        print("\(owner.id) detaching")
        self.mediator?.unregister(owner)
    }
}


public protocol MSAInteractionsManager: InteractionsManager where M: MSAMediator {
    /// Use this method to update your own initial state according to the argument, and signal interest if needed.
    func peerDiscovered(eventArgs: BroadcastArgs)
    
    /// Use this function to update your own state after another component completed its own initial state setup.
    func peerDidAttach(eventArgs: BroadcastArgs)
}


public extension MSAInteractionsManager {
    func setup() {
        guard let mediator = self.mediator,
                let owner = self.owner else { fatalError() }
        
        mediator.register(owner)
        mediator.componentDidConfigure(eventArgs: BroadcastArgs(source: owner))
    }
}
