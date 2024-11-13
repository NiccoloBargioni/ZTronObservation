import Foundation
import SwiftGraph
import os

// TODO: Can add a map from a vertex to its index in componentsGraph.vertices for performance improvements
// TODO: Consider to change `componentsIDMap` to be of type [ String: Weak<any Component> ] in case of memory leaks
public final class MSAMediator: Mediator, @unchecked Sendable {
    typealias E = WeightedGraph<String, Float>.E
    
    private var componentsGraph = WeightedGraph<String, Float>()
    private var componentsIDMap = [ String: any Component ].init()
    private var componentsMSA = [ String: [E] ].init()
    
    // A map that associates `key` component to all the other components that have an imbound edge coming from `key`
    private var flatDependencyMap = [String: [String]].init()
    private var scheduleMSAUpdate = [String: Bool].init()
    private var isRegisteringComponent: Bool = false
    
    private let logger = Logger(subsystem: "ZTronObservation", category: "MSAMediator")
    
    
    private let componentsGraphLock = DispatchSemaphore(value: 1)
    private let componentsMSALock = DispatchSemaphore(value: 1)
    private let componentsIDMapLock = DispatchSemaphore(value: 1)
    private let flatDependencyMapLock = DispatchSemaphore(value: 1)
    private let scheduleMSAUpdateLock = DispatchSemaphore(value: 1)
    private let isRegisteringComponentLock = DispatchSemaphore(value: 1)
    private let loggerLock = DispatchSemaphore(value: 1)

    public init() {  }
    
    /// Registers a component to the notification subsystem. This includes (in topological order):
    ///
    /// - Register an association between the component ID and the component itself.
    /// - Creating an empty MSA for the new component.
    /// - Modeling that there are no inbound edges to this new component.
    /// - Schedule the component's MSA for update.
    /// - Add the component ID to the components graph.
    /// - Invoking `peerDiscovered` on every other component in the graph.
    ///
    /// - Note: The new component's `peerDiscovered(_:)` should not invoke any method from Mediator other than `signalInterest(_:,_:,_:)`. Otherwise, a deadlock could result.
    ///
    /// - Complexity: time: O(V)
    public func register(_ component: any Component) {
        self.isRegisteringComponentLock.wait()
        self.isRegisteringComponent = true
        self.isRegisteringComponentLock.signal()
        
        self.componentsIDMapLock.wait()
        self.componentsMSALock.wait()
        self.flatDependencyMapLock.wait()
        self.scheduleMSAUpdateLock.wait()
        
        self.componentsIDMap[component.id] = component
        self.componentsMSA[component.id] = [E].init()
        self.flatDependencyMap[component.id] = [String].init()
        self.scheduleMSAUpdate[component.id] = true
        
        self.componentsIDMapLock.signal()
        self.scheduleMSAUpdateLock.signal()
        self.flatDependencyMapLock.signal()
        self.componentsMSALock.signal()

        
        self.componentsGraphLock.wait()
        let _ = self.componentsGraph.addVertex(component.id)
        self.componentsGraphLock.signal()

        self.componentsGraphLock.wait()
        
        defer {
            self.componentsGraphLock.signal()
        }
        
        self.componentsGraph.forEach { componentID in
            self.componentsIDMapLock.wait()
            guard let other = self.componentsIDMap[componentID] else {
                self.componentsIDMapLock.signal()
                
                self.isRegisteringComponentLock.wait()
                self.isRegisteringComponent = false
                self.isRegisteringComponentLock.signal()
                
                fatalError("Component \(componentID) has no associated components in MSAMediator map.")
            }
            self.componentsIDMapLock.signal()
            

            guard let otherDelegate = (other.getDelegate() as? (any MSAInteractionsManager)) else {
                self.isRegisteringComponentLock.wait()
                self.isRegisteringComponent = false
                self.isRegisteringComponentLock.signal()
                fatalError("Component \(componentID) is expected to have delegate of type any \(String(describing: Self.self))")
            }
            
            guard let delegate = (component.getDelegate() as? (any MSAInteractionsManager)) else {
                self.isRegisteringComponentLock.wait()
                self.isRegisteringComponent = false
                self.isRegisteringComponentLock.signal()

                fatalError("New component \(component.id) is expected to have delegate of type any \(String(describing: Self.self))")
            }
            
            if other.id != component.id {
                otherDelegate.peerDiscovered(eventArgs: BroadcastArgs(source: component))
                delegate.peerDiscovered(eventArgs: BroadcastArgs(source: other))
            }
        }
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "✓ Component \(component.id) registered")
        self.loggerLock.signal()
        #endif
        
        self.isRegisteringComponentLock.wait()
        self.isRegisteringComponent = false
        self.isRegisteringComponentLock.signal()
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
    /// - Note: The registered component's`willCheckout(_:)` must not invoke any mediator's method, otherwise a deadlock will result.
    ///
    /// - Complexity: time: O(V²), to find the component index and remove it from the dependency lists. Called unfrequently and worst case is not common.
    public func unregister(_ component: any Component) {
        
        self.componentsIDMapLock.wait()
        guard self.componentsIDMap[component.id] != nil else {
            componentsIDMapLock.signal()
            fatalError("Attempted to register \(component.id), that isn't a registered component.")
        }
        
        self.flatDependencyMapLock.wait()
        if let dependencies = self.flatDependencyMap[component.id] {
            dependencies.forEach { dependency in
                if self.componentsIDMap[dependency]?.id != component.id {
                    self.componentsIDMap[dependency]?.getDelegate()?.willCheckout(args: BroadcastArgs(source: component))
                }
            }
        }
        
        self.scheduleMSAUpdateLock.wait()
        self.markMSAForUpdates(from: component.id)

        
        self.componentsGraphLock.wait()
        componentsGraph.edgesForVertex(component.id)?.forEach { edge in
            let dest = self.componentsGraph.vertices[edge.v]
            
            self.flatDependencyMap[dest]?.removeAll { dependencyID in
                return dependencyID == component.id
            }
        }

        self.componentsGraph.removeVertex(component.id)
        self.componentsGraphLock.signal()
        
        self.componentsIDMap[component.id] = nil
        self.componentsIDMapLock.signal()
        
        self.componentsMSALock.wait()
        self.componentsMSA[component.id] = nil
        self.componentsMSALock.signal()
        
        self.flatDependencyMap[component.id] = nil
        self.flatDependencyMapLock.signal()
        
        self.scheduleMSAUpdate[component.id] = nil
        self.scheduleMSAUpdateLock.signal()
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "✓ Component \(component.id) unregistered")
        self.loggerLock.signal()
        #endif
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
        let sourceID = eventArgs.getSource().id
        
        #if DEBUG
        self.loggerLock.wait()
        logger.log(level: .debug, "ⓘ Component \(sourceID) sending notification down its MSA")
        self.loggerLock.signal()
        #endif
        
        self.componentsIDMapLock.wait()
        self.componentsGraphLock.wait()
        
        defer {
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()
        }
        
        guard self.componentsIDMap[sourceID] != nil,
              let vertexID = self.componentsGraph.indexOfVertex(sourceID) else {
            fatalError("Either you tried to push a notification down the MSA of a component that's not registered, or wtf.")
        }
        

        self.scheduleMSAUpdateLock.wait()
        if self.scheduleMSAUpdate[sourceID] == true {
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.log(level: .debug, "ⓘ Updating MSA of component \(sourceID)")
            self.loggerLock.signal()
            #endif

            self.componentsMSALock.wait()
            self.componentsMSA[sourceID] = try! self.componentsGraph.msa(root: vertexID)
            self.componentsMSALock.signal()
            self.scheduleMSAUpdate[sourceID] = false
        }
        self.scheduleMSAUpdateLock.signal()

        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "ⓘ Component \(sourceID) has MSA of size \(self.componentsMSA[sourceID]?.count ?? -1)")
        self.loggerLock.signal()
        #endif
        
        
        self.componentsMSALock.wait()
        self.componentsMSA[sourceID]?.forEach { edge in
            guard let componentToNotify = self.componentsIDMap[ self.componentsGraph.vertices[edge.v] ] else {
                self.componentsMSALock.signal()
                fatalError("Component \(self.componentsGraph.vertices[edge.v]) is not a valid component.")
            }
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.log(level: .debug, "ⓘ Sending notification \(sourceID) → \(componentToNotify.id)")
            self.loggerLock.signal()
            #endif
            
            componentToNotify.getDelegate()?.notify(args: eventArgs)
        }
        self.componentsMSALock.signal()
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
        print(#function)
        self.componentsIDMapLock.wait()
        guard let dest = self.componentsIDMap[ asker.id ]?.id,
              let origin = self.componentsIDMap[ to.id ]?.id else {
            self.componentsIDMapLock.signal()
            
            fatalError("Either \(asker.id) or \(to.id) are not registered in the notification subsystem")
        }
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "ⓘ Attaching \(origin) → \(dest)")
        self.loggerLock.signal()
        #endif

        self.isRegisteringComponentLock.wait()
        if !self.isRegisteringComponent {
            self.componentsGraphLock.wait()
        }

        self.componentsGraph.addEdge(
            from: origin,
            to: dest,
            weight: priority,
            directed: true
        )
        if !self.isRegisteringComponent {
            self.componentsGraphLock.signal()
        }
        self.isRegisteringComponentLock.signal()
        
        if self.flatDependencyMap[dest] == nil {
            self.flatDependencyMap[dest] = [String].init()
        }
        
        self.flatDependencyMap[dest]?.append(origin)
        
        self.flatDependencyMapLock.signal()
        
        self.scheduleMSAUpdateLock.wait()
        self.flatDependencyMapLock.wait()
        self.markMSAForUpdates(from: dest)
        self.componentsIDMapLock.signal()
        self.scheduleMSAUpdateLock.signal()

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
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "\(from) MSA marked for update")
        self.loggerLock.signal()
        #endif
        
        self.flatDependencyMap[from]?.forEach { parent in
            if self.scheduleMSAUpdate[parent] == false { // An attempt to break possible loops
                self.markMSAForUpdates(from: parent)
            }
        }
    }
    
    
    /// When an interaction manager completes the setup procedure, it should invoke this method to allow all the components that are interested in it to
    /// update themselves based on the consisted, ready for updates, ready state of the caller.
    internal func componentDidConfigure(eventArgs: BroadcastArgs) {
        self.componentsIDMapLock.wait()
        guard let sourceComponent = self.componentsIDMap[eventArgs.getSource().id] else {
            self.componentsIDMapLock.signal()
            fatalError("Attempted to signal completion of initial configuration for component \(eventArgs.getSource().id), that is not a valid registered component.")
        }
        
        self.componentsGraphLock.wait()
        guard let vertexID = self.componentsGraph.indexOfVertex(sourceComponent.id) else {
            self.componentsGraphLock.signal()
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.log(level: .debug, "ⓘ Component \(sourceComponent.id) not registered in graph.")
            self.loggerLock.signal()
            
            fatalError()
            #endif
        }
        self.componentsGraphLock.signal()
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "ⓘ Component \(sourceComponent.id) signalled that its configuration is complete.")
        self.loggerLock.signal()
        #endif


        self.scheduleMSAUpdateLock.wait()
        if self.scheduleMSAUpdate[sourceComponent.id] == true {
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.log(level: .debug, "ⓘ Updating MSA of component \(sourceComponent.id)")
            self.loggerLock.signal()
            #endif

            self.componentsMSALock.wait()
            self.componentsMSA[sourceComponent.id] = try! self.componentsGraph.msa(root: vertexID)
            self.scheduleMSAUpdate[sourceComponent.id] = false
        }
        self.scheduleMSAUpdateLock.signal()
        
        
        self.componentsMSA[sourceComponent.id]?.forEach { edge in
            guard let componentToNotify = self.componentsIDMap[ self.componentsGraph.vertices[edge.v] ] else {
                self.componentsMSALock.signal()
                fatalError("Component \(self.componentsGraph.vertices[edge.v]) is not a valid component.")
            }
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.log(level: .debug, "ⓘ Sending notification \(sourceComponent.id) → \(componentToNotify.id)")
            self.loggerLock.signal()
            #endif
            
            guard let componentToNotifyDelegate = componentToNotify.getDelegate() as? any MSAInteractionsManager else {
                self.componentsMSALock.signal()
                fatalError("Component to notify with id \(componentToNotify.id) was expected to have delegate of type any \(String(describing: MSAInteractionsManager.self))")
            }
            
            
            componentToNotifyDelegate.peerDidAttach(eventArgs: eventArgs)
        }
        self.componentsIDMapLock.signal()
        self.componentsMSALock.signal()
    }
    
    /// A function that converts the components graph in its DOT description, where an arrow componentA → componentB means that componentA sends notifications to componentB, or equivalently, componentB signalled insterest in componentA
    public func toDOT(_ graphName: String = "componentsGraph") -> String {
        var DOTTree = String("digraph \"\(graphName)\" {\n")
        
        self.componentsGraphLock.wait()
        self.componentsGraph.vertices.forEach { id in
            var neighboursList = String("{ ")
            let allNeighbours = self.componentsGraph.edgesForVertex(id)
            
            
            if let neighbours = allNeighbours {
                for (offset, neighbour) in neighbours.enumerated() {
                    let nodeName = self.componentsGraph[neighbour.v]
                                            
                    neighboursList.append(
                        "\"\(nodeName)\"".appending(
                            offset >= neighbours.count - 1 ? "" : ", "
                        )
                    )
                }
                
                neighboursList.append(" }")
                

                DOTTree = DOTTree.appending("""
                    "\(id)" -> \(neighboursList);\n
                """)
            }
        }
        self.componentsGraphLock.signal()
        
        DOTTree.append("}")
        return DOTTree
    }
    
    public final func MSAToDOT(for component: any Component) -> String {
        self.componentsGraphLock.wait()
        self.componentsIDMapLock.wait()
        
        if componentsGraph.indexOfVertex(component.id) == nil {
            #if DEBUG
            self.logger.warning("\(component.id) is not a valid component in the notification subsystem @ \(#function) in \(String(describing: Self.self))")
            #endif
            
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()

            
            return ""
        }
        
        self.componentsIDMapLock.signal()
            
        var DOTTree = String("digraph \"\(component.id) MSA\" {\n")
        DOTTree.append("node [shape = circle, ordering=out];\n")
        
        self.componentsMSALock.wait()
        guard let MSAOfComponent = self.componentsMSA[component.id] else {
            #if DEBUG
            self.logger.error("No MSA for \(component.id) in notification subsystem @ \(#function) in \(String(describing: Self.self))")
            #endif
            self.componentsMSALock.signal()
            return ""
        }
        self.componentsMSALock.signal()
        
        MSAOfComponent.forEach { edge in
            let uID = self.componentsGraph.vertexAtIndex(edge.u)
            let vID = self.componentsGraph.vertexAtIndex(edge.v)
            
            DOTTree.append("\"\(uID)\" -> \"\(vID)\" [label=\(edge.weight)];\n")
        }
        
        DOTTree.append("}")
        
        self.componentsGraphLock.signal()
        
        return DOTTree
    }
}
