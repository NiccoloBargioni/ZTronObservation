import Foundation
import SwiftGraph

// TODO: Can add a map from a vertex to its index in componentsGraph.vertices for performance improvements
public class MSAMediator: Mediator {
    typealias E = WeightedGraph<String, Float>.E
    
    private var componentsGraph = WeightedGraph<String, Float>()
    private var componentsIDMap = [ String: any Component ].init()
    private var componentsMSA = [ String: [E] ].init()
    
    // A map that associates `key` component to all the other components that have an imbound edge coming from `key`
    private var flatDependencyMap = [String: [String]].init()
    private var scheduleMSAUpdate = [String: Bool].init()
    
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
            
            otherDelegate.peerDiscovered(eventArgs: BroadcastArgs(source: component))
            delegate.peerDiscovered(eventArgs: BroadcastArgs(source: other))
        }
        
        
        print("\(component.id) did register")
    }
    
    /// - Complexity: time: O(V²), to find the component index and remove it from the dependency lists. Called unfrequently and worst case is not common.
    public func unregister(_ component: any Component) {
        if let dependencies = self.flatDependencyMap[component.id] {
            dependencies.forEach { dependency in
                self.componentsIDMap[dependency]?.delegate?.willCheckout(args: BroadcastArgs(source: component))
            }
        }
        
        self.markMSAAForUpdates(from: component.id)

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
    
    /// - Complexity: Time: O(V + E + V·log(V)), Space: O(E+V). Though in most cases time is O(V)
    public func pushNotification(eventArgs: BroadcastArgs) {
        print("\(eventArgs.getSource().id) will push notification")
        let sourceID = eventArgs.getSource().id
        guard self.componentsIDMap[sourceID] != nil,
              let vertexID = self.componentsGraph.indexOfVertex(sourceID) else { fatalError() }
        
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
    

    /// - Complexity: time: O(V), to recursively mark MSA of parents as needing update.
    public func signalInterest(_ asker: any Component, to: any Component, priority: Float = 1.0) {
        guard let dest = self.componentsIDMap[ asker.id ]?.id,
              let origin = self.componentsIDMap[ to.id ]?.id else { fatalError() }
        
        print("Attaching \(origin) --> \(dest)")

        
        self.componentsGraph.addEdge(
            from: origin,
            to: dest,
            weight: priority,
            directed: true
        )
        
        self.markMSAAForUpdates(from: dest)
        
        if self.flatDependencyMap[dest] == nil {
            self.flatDependencyMap[dest] = [String].init()
        }
        
        self.flatDependencyMap[dest]?.append(origin)
    }
    
    /// - Complexity: time: O(V), space: O(1)
    private func markMSAAForUpdates(from: String) {
        guard self.componentsIDMap[from] != nil else { return }
        
        self.scheduleMSAUpdate[from] = true
        
        self.flatDependencyMap[from]?.forEach { parent in
            self.markMSAAForUpdates(from: parent)
        }
    }
    
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
