import Foundation
import SwiftGraph

// TODO: Can add a map from a vertex to its index in componentsGraph.vertices for performance improvements
// TODO: Consider to change `componentsIDMap` to be of type [ String: Weak<any Component> ] in case of memory leaks
public class MSAMediator: Mediator {
    typealias E = WeightedGraph<String, Float>.E
    
    private var componentsGraph = WeightedGraph<String, Float>()
    private var componentsIDMap = [ String: any Component ].init()
    private var componentsMSA = [ String: [E] ].init()
    
    // A map that associates `key` component to all the other components that have an imbound edge coming from `key`
    private var flatDependencyMap = [String: [String]].init()
    private var scheduleMSAUpdate = [String: Bool].init()
    
    /// Registers a component to the notification subsystem. This includes (in topological order):
    ///
    /// - Register an association between the component ID and the component itself.
    /// - Creating an empty MSA for the new component.
    /// - Modeling that there are no inbound edges to this new component.
    /// - Schedule the component's MSA for update.
    /// - Add the component ID to the components graph.
    /// - Invoking `peerDiscovered` on every other component in the graph.
    ///
    /// - Complexity: time: O(V)
    public func register(_ component: any Component) {
        print("\(component.id) will register")
        
        self.componentsIDMap[component.id] = component
        self.componentsMSA[component.id] = [E].init()
        self.flatDependencyMap[component.id] = [String].init()
        self.scheduleMSAUpdate[component.id] = true
        
        let _ = self.componentsGraph.addVertex(component.id)

        self.componentsGraph.forEach { componentID in
            guard let other = self.componentsIDMap[componentID] else { fatalError() }
            guard let otherDelegate = (other.delegate as? (any MSAInteractionsManager)) else { fatalError() }
            guard let delegate = (component.delegate as? (any MSAInteractionsManager)) else { fatalError() }
            
            if other.id != component.id {
                otherDelegate.peerDiscovered(eventArgs: BroadcastArgs(source: component))
                delegate.peerDiscovered(eventArgs: BroadcastArgs(source: other))
            }
        }
        
        
        print("\(component.id) did register")
    }
    
    
    /// Unregister a component from the subsystem, provided it was registered.
    ///
    /// - Parameter component: The component to remove from the dependencies graph.
    ///
    /// - Invokes method `willCheckout` on every other component that can reach `component`.
    /// - Marks the MSA of all the component that could reach `component` as needing update.
    /// - For each neighbour `n` of `component`, removes `component` from the dependency list of `n`.
    /// - Removeds the `component` from the graph.
    /// - Removes the `component` from the ID -> Component map.
    /// - Removes the `component`'s MSA.
    /// - Removes the dependency list of the `component`.
    /// - Removes the `component` from the MSA updates schedule.
    ///
    /// - Note: This implementation makes self-use of `markMSAForUpdates`
    ///
    /// - Complexity: time: O(V²), to find the component index and remove it from the dependency lists. Called unfrequently and worst case is not common.
    public func unregister(_ component: any Component) {
        guard self.componentsIDMap[component.id] != nil else {
            fatalError("Attempted to register \(component.id), that isn't a registered component.")
        }
        
        if let dependencies = self.flatDependencyMap[component.id] {
            dependencies.forEach { dependency in
                if self.componentsIDMap[dependency]?.id != component.id {
                    self.componentsIDMap[dependency]?.delegate?.willCheckout(args: BroadcastArgs(source: component))
                }
            }
        }
        
        self.markMSAForUpdates(from: component.id)

        componentsGraph.edgesForVertex(component.id)?.forEach { edge in
            let dest = self.componentsGraph.vertices[edge.v]
            
            self.flatDependencyMap[dest]?.removeAll { dependencyID in
                return dependencyID == component.id
            }
        }

        self.componentsGraph.removeVertex(component.id)
        self.componentsIDMap[component.id] = nil
        self.componentsMSA[component.id] = nil
        
        
        self.flatDependencyMap[component.id] = nil
        self.scheduleMSAUpdate[component.id] = nil
    }
    
    
    /// Sends a notification to all nodes in the MSA of `eventArgs.getSource()`.
    ///
    /// If the MSA rooted in `eventArgs.getSource()` needs to be recomputed, its update its performed (including when a component sends its first notification).
    /// An update consists of invoking `notify(_:)` on the delegate of each component in some MSA.
    ///
    /// - Note: No order of notification is guaranteed, not even topological.
    /// - Note: `eventArgs.getSource()` must be a valid, registered component in the notification subsystem, otherwise `fatalError()` is raised.
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V). Though in most cases time is O(V)
    public func pushNotification(eventArgs: BroadcastArgs) {
        print("\(eventArgs.getSource().id) will push notification")
        let sourceID = eventArgs.getSource().id
        
        guard self.componentsIDMap[sourceID] != nil,
              let vertexID = self.componentsGraph.indexOfVertex(sourceID) else {
            fatalError("Either you tried to push a notification down the MSA of a component that's not registered, or wtf.")
        }
        
        if self.scheduleMSAUpdate[sourceID] == true {
            self.componentsMSA[sourceID] = try! self.componentsGraph.msa(root: vertexID)
                
            self.scheduleMSAUpdate[sourceID] = false
        }
        
        print("Component \(sourceID) has MSA of size \(self.componentsGraph.edgesForVertex(sourceID)?.count ?? -1)")
        
        self.componentsMSA[sourceID]?.forEach { edge in
            guard let componentToNotify = self.componentsIDMap[ self.componentsGraph.vertices[edge.v] ] else { fatalError() }
            print("Sending notification from \(eventArgs.getSource().id) to \(componentToNotify.id)")
            componentToNotify.delegate?.notify(args: eventArgs)
        }
    }
    

    /// Creates a relationship `to → asker`, where the edge has weight `priority`.
    /// In other words, use this method to request that `asker` receives notification from `to`.
    ///
    /// - Parameter asker: The component interested in receiving notifications.
    /// - Parameter to: The component that should send notifications to `asker`.
    /// - Parameter priority: Use this parameter to specify the weight of the link `to → asker`.
    /// In the greater scheme of things, design weights to favor some paths of notification (with lower total weight) over others.
    ///
    /// - Also appends `asker` in the list of components that have an inbound edge toward `to`, for purposes of scheduling MSA updates.
    ///
    /// - Note: This implementation makes self use of `markMSAForUpdates(_:)`.
    ///
    /// - Complexity: time: O(V), to recursively mark MSA of parents as needing update.
    public func signalInterest(_ asker: any Component, to: any Component, priority: Float = 1.0) {
        guard let dest = self.componentsIDMap[ asker.id ]?.id,
              let origin = self.componentsIDMap[ to.id ]?.id else {
            fatalError("Either \(asker.id) or \(to.id) are not registered in the notification subsystem")
        }
        
        print("Attaching \(origin) --> \(dest)")

        
        self.componentsGraph.addEdge(
            from: origin,
            to: dest,
            weight: priority,
            directed: true
        )
        
        self.markMSAForUpdates(from: dest)
        
        if self.flatDependencyMap[dest] == nil {
            self.flatDependencyMap[dest] = [String].init()
        }
        
        self.flatDependencyMap[dest]?.append(origin)
    }
    
    /// Starting from a valid component in the graph, it marks such component for MSA updates, then it marks all the nodes that have
    /// an inbound edge toward it for updates as well, propagating upwards.
    ///
    /// - Note: Needs testing when loops in the components graph exist.
    ///
    /// - Complexity: time: O(V), space: O(1)
    private func markMSAForUpdates(from: String) {
        guard self.componentsIDMap[from] != nil else { return }
        
        self.scheduleMSAUpdate[from] = true
        
        self.flatDependencyMap[from]?.forEach { parent in
            if self.scheduleMSAUpdate[parent] == false { // An attempt to break possible loops
                self.markMSAForUpdates(from: parent)
            }
        }
    }
    
    
    /// When an interaction manager completes the setup procedure, it should invoke this method to allow all the components that are interested in it to
    /// update themselves based on the consisted, ready for updates, ready state of the caller.
    internal func componentDidConfigure(eventArgs: BroadcastArgs) {
        print("\(eventArgs.getSource().id) did configure")
        self.componentsIDMap.keys.forEach { componentID in
            if componentID != eventArgs.getSource().id {
                guard let theComponent = self.componentsIDMap[componentID] else { fatalError() }
                guard let theDelegate = (theComponent.delegate as? any MSAInteractionsManager) else { fatalError() }
                
                theDelegate.peerDidAttach(eventArgs: BroadcastArgs(source: theComponent))
            }
        }
    }
}
