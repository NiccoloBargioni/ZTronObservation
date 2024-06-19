import Foundation

/// A `Mediator` instance that handles notifications using a broadcast system: a notification from a changed component is dispatched to every other
/// registered component (equality between components is tested based on both their `.id` and dynamic types).
///
/// This mediator can't guarantee non-redundancy of the notifications, as it is responsibility of the component to ignore notifications it is not interested in.
public class BroadcastMediator: Mediator {
    public static func == (lhs: BroadcastMediator, rhs: BroadcastMediator) -> Bool {
        return lhs.id == rhs.id
    }

    public var id: String = "broadcast mediator"
    private var listeners: [any Component] = .init()
    private var registerQueue: DispatchQueue

    public init() {
        self.registerQueue = DispatchQueue(label: "com.zombietron.\(id).serial", qos: .background)
    }
    
    /// Broadcasts a change to all the listeners.
    ///
    /// - Complexity: **Time**: O(listeners.count), **Memory**: O(1)
    public func pushNotification(eventArgs: BroadcastArgs) {
        let changedComponent = eventArgs.getSource()
        
        self.listeners.forEach { component in
            if component.id != changedComponent.id
                && type(of: component) != type(of: changedComponent) {
                component.delegate?.notify(args: eventArgs)
            }
        }
    }

    /// Registers a new listener passed as a parameter.
    ///
    /// - Note: As a side effect, if another listener with the same id as the parameter `listener` is already registered,
    /// the previous one gets replaced with the new one.
    ///
    /// - Note: This method is asynchronously executed on a serial queue with `.background` QoS.
    ///
    /// - Complexity: **Time**: O(listeners.count) to find listeners of the same id and type as the new subscriber. **Memory**: O(1)
    public func register(_ listener: any Component) {
        self.registerQueue.sync {
            self.listeners.removeAll { subscriber in
                return listener.id == subscriber.id
                    && type(of: listener) == type(of: subscriber)
            }

            self.listeners.append(listener)
        }
    }

    /// Removes the specified listener, by comparing their `id`s.
    ///
    /// - Note: This method is asynchronously executed on a serial queue with `.background` QoS.
    ///
    /// - Complexity: **Time**: O(listeners.count), **Memory**: O(1)
    public func unregister(_ listener: any Component) {
        self.registerQueue.sync {
            self.listeners.removeAll { subscriber in
                return subscriber.id == listener.id 
                    && type(of: subscriber) == type(of: listener)
            }
        }
    }
}
