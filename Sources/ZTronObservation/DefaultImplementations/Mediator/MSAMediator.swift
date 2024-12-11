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
    // private var flatDependencyMap = [String: [String]].init()
    private var scheduleMSAUpdate = [String: Bool].init()
    
    private let logger = Logger(subsystem: "ZTronObservation", category: "MSAMediator")
    
    
    private let componentsGraphLock = DispatchSemaphore(value: 1)
    private let componentsMSALock = DispatchSemaphore(value: 1)
    private let componentsIDMapLock = DispatchSemaphore(value: 1)
    private let scheduleMSAUpdateLock = DispatchSemaphore(value: 1)
    private let loggerLock = DispatchSemaphore(value: 1)
    private let sequentialAccessLock = DispatchSemaphore(value: 1)

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
    /// - Parameter component: The component to add to the notification subsystem.
    /// - Parameter or: Specifies how to handle attempted registration of a component when another with the same ID already exists.
    ///
    /// - Complexity: time: O(V)
    public func register(
        _ component: any Component,
        or: OnRegisterConflict = .replace
    ) {
        self.sequentialAccessLock.wait()
        #if DEBUG
        self.loggerLock.wait()
        self.logger.info("ⓘ Registering \(component.id)")
        self.loggerLock.signal()
        #endif
        self.componentsIDMapLock.wait()
        let componentExists: Bool = componentsIDMap[component.id] != nil
        self.componentsIDMapLock.signal()

        if or == .replace {
            if componentExists {
                #if DEBUG
                self.loggerLock.wait()
                self.logger.warning("⚠️ Attempted to register \(component.id) with the same id of another that's already part of the notification subsystem. Replacing.")
                self.loggerLock.signal()
                #endif
                self.componentsIDMapLock.wait()
                let oldComponentWithSameID = self.componentsIDMap[component.id]
                self.componentsIDMapLock.signal()
                
                #if DEBUG
                self.loggerLock.wait()
                if oldComponentWithSameID === component {
                    self.logger.warning("⚠️ Attempting to .replace a component \(component.id) with a referentially equal component..")
                } else {
                    self.logger.warning("⚠️ Attempting to .replace a component \(component.id) with a referentially different component.")
                }
                self.loggerLock.signal()
                #endif
                
                if let oldComponentWithSameID = oldComponentWithSameID {
                    self.sequentialAccessLock.signal()
                    self.unregister(oldComponentWithSameID)
                    self.sequentialAccessLock.wait()
                }
            }
        } else {
            if componentExists {
                #if DEBUG
                self.loggerLock.wait()
                self.logger.warning("⚠️ Attempted to register \(component.id) with the same id of another that's already part of the notification subsystem. Ignoring.")
                self.loggerLock.signal()
                #endif
                self.sequentialAccessLock.signal()
                return
            }
        }
        
        self.componentsIDMapLock.wait()
        self.componentsMSALock.wait()
        self.scheduleMSAUpdateLock.wait()
        
        self.componentsIDMap[component.id] = component
        self.componentsMSA[component.id] = [E].init()
        self.scheduleMSAUpdate[component.id] = true
        
        self.componentsIDMapLock.signal()
        self.scheduleMSAUpdateLock.signal()
        self.componentsMSALock.signal()

        
        self.componentsGraphLock.wait()
        let _ = self.componentsGraph.addVertex(component.id)
        self.componentsGraphLock.signal()

        self.componentsGraphLock.wait()
        
        defer {
            self.componentsGraphLock.signal()
        }

        var otherDelegates: [(any Component)] = []
        
        self.componentsGraph.forEach { componentID in
            self.componentsIDMapLock.wait()
            guard let other = self.componentsIDMap[componentID] else {
                self.componentsIDMapLock.signal()
                self.sequentialAccessLock.signal()
                fatalError("❌ Component \(componentID) has no associated components in MSAMediator map.")
            }
            self.componentsIDMapLock.signal()
            
                        
            if other.id != component.id {
                otherDelegates.append(other)
            }
        }
        
        self.sequentialAccessLock.signal()

        guard let delegate = (component.getDelegate() as? (any MSAInteractionsManager)) else {
            fatalError("❌ New component \(component.id) is expected to have delegate of type any \(String(describing: MSAInteractionsManager.self)). Found \(String(describing: type(of: component.getDelegate()))) instead.")
        }

        otherDelegates.forEach { other in
            guard let otherDelegate = (other.getDelegate() as? (any MSAInteractionsManager)) else {
                fatalError("❌ Component \(other.id) is expected to have delegate of type any \(String(describing: MSAInteractionsManager.self)). Found \(String(describing: type(of: other.getDelegate()))) instead")
            }
            
            otherDelegate.peerDiscovered(eventArgs: BroadcastArgs(source: component))
            delegate.peerDiscovered(eventArgs: BroadcastArgs(source: other))
        }
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "✅ Component \(component.id) registered")
        self.loggerLock.signal()
        #endif
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
    public func unregister(_ component: any Component, or: OnUnregisterConflict = .fail) {
        self.sequentialAccessLock.wait()
        self.loggerLock.wait()
        self.logger.info("ⓘ Unregistering \(component.id)")
        self.loggerLock.signal()

        self.componentsIDMapLock.wait()
        guard self.componentsIDMap[component.id] != nil else {
            if or == .fail {
                self.componentsIDMapLock.signal()
                self.sequentialAccessLock.signal()
                fatalError("❌ Attempted to unregister \(component.id), that isn't a registered component.")
            } else {
                #if DEBUG
                self.loggerLock.wait()
                self.logger.warning("⚠️ Attempted to unregister \(component.id), that isn't a registered component. Ignoring")
                self.loggerLock.signal()
                #endif
                
                self.sequentialAccessLock.signal()
                self.componentsIDMapLock.signal()
                return
            }
        }
        
        self.componentsMSALock.wait()
        self.componentsGraphLock.wait()
        
        let componentsToCheckoutTo = self.componentsMSA[component.id]?.compactMap { edge in
            if edge.v < componentsGraph.vertexCount {
                return self.componentsIDMap[componentsGraph[edge.v]]
            } else {
                return nil
            }
        }
        
        self.componentsMSALock.signal()
        self.componentsGraphLock.signal()
        self.sequentialAccessLock.signal()
        
        componentsToCheckoutTo?.forEach { reachableComponent in
            reachableComponent.getDelegate()?.willCheckout(args: BroadcastArgs(source: component))
        }

        self.componentsGraphLock.wait()
        self.sequentialAccessLock.wait()
                
        self.scheduleMSAUpdateLock.wait()
        self.markMSAForUpdates(from: component.id)
        self.scheduleMSAUpdate[component.id] = nil
        
        self.componentsGraphLock.signal()
        
        self.componentsIDMap[component.id] = nil
        self.componentsIDMapLock.signal()
        
        self.componentsMSALock.wait()
        self.componentsMSA[component.id] = nil
        self.componentsMSALock.signal()
        
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.log(level: .debug, "✅ Component \(component.id) unregistered")
        self.loggerLock.signal()
        
        self.componentsGraphLock.wait()
        self.componentsGraph.removeVertex(component.id)

        self.componentsGraph.forEach { componentID in
            assert(componentID != component.id)
        }

        self.componentsMSALock.wait()
        self.componentsIDMapLock.wait()
        
        self.componentsIDMapLock.signal()
        self.scheduleMSAUpdateLock.signal()
        self.componentsMSALock.signal()
        self.componentsGraphLock.signal()
        #endif
    
        self.sequentialAccessLock.signal()

    }
    
    
    /// Sends a notification to all nodes in the MSA of `eventArgs.getSource()`.
    ///
    /// If the MSA rooted in `eventArgs.getSource()` needs to be recomputed, its update its performed (including when a component sends its first notification).
    /// An update consists of invoking `notify(_:)` on the delegate of each component in some MSA.
    ///
    /// - Parameter limitToNeighbours: If `true`, components that transitively depend on `eventArgs.getSource()` aren't notified, else, its whole MSA is notified.
    /// - Parameter completion: A callback executed after all components were notified. If at least one component's `notify(_:)` executes async code, it's not guaranteed that this callbacks executes after all the notifications are handled.
    ///
    /// - Note: No order of notification is guaranteed, not even topological.
    /// - Note: `eventArgs.getSource()` must be a valid, registered component in the notification subsystem, otherwise `fatalError()` is raised.
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V). Though in most cases time is O(V)
    public func pushNotification(eventArgs: BroadcastArgs, limitToNeighbours: Bool, completion: (() -> Void)? = nil) {
        self.sequentialAccessLock.wait()
        let sourceID = eventArgs.getSource().id
        
        #if DEBUG
        self.loggerLock.wait()
        logger.info("ⓘ Component \(sourceID) sending notification down its MSA")
        self.loggerLock.signal()
        #endif
        
        self.componentsIDMapLock.wait()
        self.componentsGraphLock.wait()
        
        guard self.componentsIDMap[eventArgs.getSource().id] != nil && self.componentsGraph.indexOfVertex(eventArgs.getSource().id) != nil else {
            #if DEBUG
            self.loggerLock.wait()
            self.logger.warning("⚠️ Attempted to push notification from \(eventArgs.getSource().id), that's not a registered component. \(#function) aborted.")
            self.loggerLock.signal()
            #endif
            
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()
            self.sequentialAccessLock.signal()
            return
        }
        
        var componentsToNotify: [(any Component, any Component)] = .init()

        if limitToNeighbours {
            componentsGraph.edgesForVertex(sourceID)?.forEach { edge in
                if componentsGraph[edge.u] == sourceID {
                    if let dest = self.componentsIDMap[self.componentsGraph[edge.v]] {
                        componentsToNotify.append(
                            (dest, eventArgs.getSource())
                        )
                    }
                }
            }
            
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()
        } else {
            self.componentsMSALock.wait()
            self.scheduleMSAUpdateLock.wait()
            self.updateMSAIfNeeded(of: eventArgs.getSource())

            #if DEBUG
            self.loggerLock.wait()
            self.logger.info("ⓘ Component \(sourceID) has MSA of size \(self.componentsMSA[sourceID]?.count ?? -1)")
            self.loggerLock.signal()
            #endif
            
            self.componentsMSA[sourceID]?.forEach { edge in
                if edge.u >= self.componentsGraph.vertexCount {
                    self.scheduleMSAUpdate[sourceID] = true
                    return
                } else {
                    guard let dependency = self.componentsIDMap[ self.componentsGraph.vertices[edge.u] ] else {
                        self.componentsMSALock.signal()
                        self.componentsIDMapLock.signal()
                        self.componentsGraphLock.signal()
                        fatalError("❌ Component \(self.componentsGraph.vertices[edge.u]) is not a valid component.")
                    }
                    guard let componentToNotify = self.componentsIDMap[ self.componentsGraph.vertices[edge.v] ] else {
                        self.componentsIDMapLock.signal()
                        self.componentsGraphLock.signal()
                        self.componentsMSALock.signal()
                        fatalError("❌ Component \(self.componentsGraph.vertices[edge.v]) is not a valid component.")
                    }
                    
                    componentsToNotify.append((componentToNotify, dependency))
                }
            }
            
            self.componentsMSALock.signal()
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()
            self.scheduleMSAUpdateLock.signal()
        }
        
        self.sequentialAccessLock.signal()
        
        componentsToNotify.forEach { component, dependency in
            #if DEBUG
            self.loggerLock.wait()
            self.logger.info("ⓘ Will send notification \(sourceID) → \(sourceID != dependency.id ? "\(dependency.id) → " : "")\(component.id)")
            self.loggerLock.signal()
            #endif

            component.getDelegate()?.notify(args: MSAArgs(from: dependency, payload: eventArgs))
        }
        
        completion?()
        
    }
    

    /// Creates a relationship `to → asker`, where the edge has weight `priority`.
    /// In other words, use this method to request that `asker` receives notification from `to`.
    ///
    /// - Parameter asker: The component interested in receiving notifications.
    /// - Parameter to: The component that should send notifications to `asker`.
    /// - Parameter priority: Use this parameter to specify the weight of the link `to → asker`. In the greater scheme of things, design weights to favor some paths of notification (with lower total weight) over others
    /// - Parameter or: In concurrent environment it's possible that very short-lived components exist.
    /// A component might unregister before another component has a chance to complete its `signalInterest(_:,_:,_:)` call. Use this
    /// parameter to disambiguate how to handle this scenario. Defaults to `.fail`.
    ///
    /// - Returns: `true`, if was able to attach `to → asker`, `false` otherwise.
    ///
    /// - Note: This implementation makes self use of `markMSAForUpdates(_:)`.
    /// - Complexity: time: O(V + E), to recursively mark MSA of parents as needing update.
    @discardableResult public func signalInterest(_ asker: any Component, to: any Component, priority: Float = 1.0, or: OnSignalInterestFail = .fail) -> Bool {
        self.sequentialAccessLock.wait()
        self.componentsIDMapLock.wait()
        guard let dest = self.componentsIDMap[ asker.id ]?.id,
              let origin = self.componentsIDMap[ to.id ]?.id else {
            self.componentsIDMapLock.signal()
            
            if or == .fail {
                fatalError("❌ Either \(asker.id) or \(to.id) are not registered in the notification subsystem in \(#function)")
            } else {
                self.loggerLock.wait()
                self.logger.warning("⚠️ Attempting to attach \(to.id) → \(asker.id), but at least one of those is not registered in the notification subsystem. Ignoring.")
                self.loggerLock.signal()
                self.sequentialAccessLock.signal()
                return false
            }
        }
        
        if origin == dest {
            self.loggerLock.wait()
            self.logger.warning("⚠️ Attempting to attach \(origin) → \(dest), which is a self loop. This is not allowed.")
            self.loggerLock.signal()
            return false
        }
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.info("ⓘ Attaching \(origin) → \(dest)")
        self.loggerLock.signal()
        #endif

        if let outboundEdgesOfOrigin = self.componentsGraph.edgesForVertex(origin) { // O(V)
            if outboundEdgesOfOrigin.reduce(false, { destinationEdgeExists, nextEdge in
                return destinationEdgeExists || self.componentsGraph[nextEdge.v] == dest
            }) {
            #if DEBUG
                self.loggerLock.wait()
                self.logger.warning("⚠️ Attempted to register an edge between \(origin) and \(dest) that already exists. Cancelling the registration")
                self.loggerLock.signal()
            #endif
                self.componentsGraphLock.signal()
                self.componentsIDMapLock.signal()
                self.sequentialAccessLock.signal()
                return false
            }
        }
            
        self.componentsGraph.addEdge(
            from: origin,
            to: dest,
            weight: priority,
            directed: true
        )
        
        self.scheduleMSAUpdateLock.wait()
        self.markMSAForUpdates(from: dest)
        self.scheduleMSAUpdateLock.signal()

        self.componentsIDMapLock.signal()
        self.sequentialAccessLock.signal()
        
        return true
    }
    
    /// Starting from a valid component in the graph, it marks such component for MSA updates, then it marks all the nodes that have
    /// an inbound edge toward it for updates as well, propagating upwards.
    ///
    /// - Parameter from: The ID of the components whose dependency subtree might have changed.
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V)
    ///
    /// - componentsGraphLock
    /// - componentsIDMapLock
    /// - scheduleMSAUpdateLock
    private func markMSAForUpdates(from: String) {
        guard self.componentsIDMap[from] != nil else { return }
        
        self.scheduleMSAUpdate[from] = true
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.info("ⓘ \(from) MSA marked for update")
        self.loggerLock.signal()
        #endif
        
        let reverseGraph = self.componentsGraph.reversed() // O(E)
        
        guard let reversedFrom = reverseGraph.indexOfVertex(from) else {
            #if DEBUG
            self.loggerLock.wait()
            self.logger.error("❌ Could not find origin \(from) to mark reachable components' MSA for update.")
            self.loggerLock.signal()
            #endif
            fatalError()
        }
        
        #if DEBUG
        self.loggerLock.wait()
        #endif
        let reachableComponents = try! reverseGraph.msa(root: reversedFrom)
        reachableComponents.forEach { reachableComponent in
            let reachable = reverseGraph[reachableComponent.v]
            #if DEBUG
            self.logger.info("ⓘ \(reachable) reachable from \(from) and scheduled for update")
            #endif
            self.scheduleMSAUpdate[reachable] = true
        }
        
        #if DEBUG
        self.loggerLock.signal()
        #endif
    }
    
    
    /// When an interaction manager completes the setup procedure, it should invoke this method to allow all the components that are interested in it to
    /// update themselves based on the consisted, ready for updates, ready state of the caller.
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V)
    public final func componentDidConfigure(eventArgs: BroadcastArgs) {
        self.sequentialAccessLock.wait()
        self.componentsIDMapLock.wait()
        guard let sourceComponent = self.componentsIDMap[eventArgs.getSource().id] else {
            self.componentsIDMapLock.signal()
            self.sequentialAccessLock.signal()
            fatalError("❌ Attempted to signal completion of initial configuration for component \(eventArgs.getSource().id), that is not a valid registered component.")
        }
        
        self.componentsGraphLock.wait()
        self.componentsMSALock.wait()
        self.scheduleMSAUpdateLock.wait()
        self.updateMSAIfNeeded(of: eventArgs.getSource())
        self.scheduleMSAUpdateLock.signal()
        self.componentsMSALock.signal()
        self.componentsGraphLock.signal()
        
        #if DEBUG
        self.loggerLock.wait()
        self.logger.info("ⓘ Component \(sourceComponent.id) signalled that its configuration is complete.")
        self.loggerLock.signal()
        #endif
        
        
        var componentsToNotifyDelegates: [any MSAInteractionsManager] = .init()
        
        self.componentsMSA[sourceComponent.id]?.forEach { edge in
            guard let componentToNotify = self.componentsIDMap[ self.componentsGraph.vertices[edge.v] ] else {
                self.componentsMSALock.signal()
                fatalError("❌ Component \(self.componentsGraph.vertices[edge.v]) is not a valid component.")
            }
                        
            guard let componentToNotifyDelegate = componentToNotify.getDelegate() as? any MSAInteractionsManager else {
                self.componentsMSALock.signal()
                fatalError("❌ Component to notify with id \(componentToNotify.id) was expected to have delegate of type any \(String(describing: MSAInteractionsManager.self))")
            }
            
            componentsToNotifyDelegates.append(componentToNotifyDelegate)
        }
        self.componentsIDMapLock.signal()
        self.componentsMSALock.signal()
        self.sequentialAccessLock.signal()
        
        componentsToNotifyDelegates.forEach { delegate in
            if let owner = delegate.getOwner() {
                #if DEBUG
                self.loggerLock.wait()
                self.logger.info("ⓘ Sending componentDidConfigure notification \(sourceComponent.id) → \(owner.id)")
                self.loggerLock.signal()
                #endif
                
                delegate.peerDidAttach(eventArgs: eventArgs)
            }
        }
    }
    
    /// A function that converts the components graph in its DOT description, where an arrow componentA → componentB means that componentA sends notifications to componentB, or equivalently, componentB signalled insterest in componentA
    ///
    /// Locks the following semaphores:
    /// - componentsGraphLock
    ///
    /// - Complexity: O(V+E) in time, O(1) in space
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
    
    /// Uses the following locks:
    ///
    /// - Complexity: Time: O(E + V·log(V)) if MSA of `component` needs update, O(V+E) otherwise, Space: O(E+V) if MSA of `component` needs update, O(1) otherwise.
    ///
    /// Locks the following semaphores:
    /// - componentsGraphLock
    /// - componentsIDMapLock
    /// - componentsMSALock
    /// - scheduleMSAUpdateLock
    public final func MSAToDOT(for component: any Component) -> String {
        self.componentsGraphLock.wait()
        self.componentsIDMapLock.wait()
        
        if componentsGraph.indexOfVertex(component.id) == nil {
            #if DEBUG
            self.logger.warning("⚠️ \(component.id) is not a valid component in the notification subsystem @ \(#function) in \(String(describing: Self.self))")
            #endif
            
            self.componentsIDMapLock.signal()
            self.componentsGraphLock.signal()
            
            return ""
        }
        
        self.componentsMSALock.wait()
        self.scheduleMSAUpdateLock.wait()
        self.updateMSAIfNeeded(of: component)
        self.scheduleMSAUpdateLock.signal()
        self.componentsMSALock.signal()
        
        self.componentsIDMapLock.signal()
            
        var DOTTree = String("digraph \"\(component.id) MSA\" {\n")
        DOTTree.append("node [shape = circle, ordering=out];\n")
        
        
        self.componentsMSALock.wait()
        guard let MSAOfComponent = self.componentsMSA[component.id] else {
            #if DEBUG
            self.logger.error("❌ No MSA for \(component.id) in notification subsystem @ \(#function) in \(String(describing: Self.self))")
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
    
    
    /// Updates the MSA of the specified component. The caller of this function should make sure to have locked the following semaphores:
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V)
    ///
    /// - scheduleMSAUpdateLock
    /// - componentsIDMapLock
    /// - componentsGraphLock
    /// - componentsMSALock
    private func updateMSAIfNeeded(of component: any Component) {
        guard self.componentsIDMap[component.id] != nil,
              let vertexID = self.componentsGraph.indexOfVertex(component.id) else {
            fatalError("❌ Attempted to update MSA of a component that's not part of the notification subsystem")
        }
        

        if self.scheduleMSAUpdate[component.id] == true {
            
            #if DEBUG
            self.loggerLock.wait()
            self.logger.info("ⓘ Updating MSA of component \(component.id)")
            self.loggerLock.signal()
            #endif

            self.componentsMSA[component.id] = try! self.componentsGraph.msa(root: vertexID)
            
            var allVerticesInMSA: Set<String> = .init()
            
            self.componentsMSA[component.id]?.forEach { edge in
                allVerticesInMSA.insert(self.componentsGraph[edge.u])
                allVerticesInMSA.insert(self.componentsGraph[edge.v])
            }
            
            let msaGraph = WeightedGraph<String, Float>.init(vertices: Array(allVerticesInMSA))
            self.componentsMSA[component.id]?.forEach { edge in
                msaGraph.addEdge(from: self.componentsGraph[edge.u], to: self.componentsGraph[edge.v], weight: 1.0, directed: true)
            }

            #if DEBUG
            // Assert that the root of the computed MSA is `component` parameter.
            if msaGraph.vertices.count > 0 {
                assert(msaGraph.isDAG == true)
                assert(msaGraph.findTreeRoot() != nil)
                
                let treeRootID: String? = msaGraph.vertices.first { componentID in
                    let index = msaGraph.indexOfVertex(componentID)
                    if let index = index {
                        let indegreeOfComponent = msaGraph.indegreeOfVertex(at: index)
                        
                        return indegreeOfComponent <= 0
                    } else {
                        return false
                    }
                }
                
                assert(treeRootID == component.id)
            }
            #endif
            
            self.scheduleMSAUpdate[component.id] = false
        }
    }
    
}
