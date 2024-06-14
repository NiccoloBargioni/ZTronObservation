import SwiftGraph

public struct MSAResult<V,W> where 
        V: Decodable & Encodable & Equatable,
        W: Decodable & Encodable & Equatable & Numeric & Comparable {
    internal let arborescence: WeightedGraph<V, W>
    internal let minCost: W
    
    init(arborescence: WeightedGraph<V, W>, minCost: W) {
        self.arborescence = arborescence
        self.minCost = minCost
    }
    
    public func getArborescence() -> WeightedGraph<V, W> {
        return arborescence
    }
    
    public func getMinCost() -> W {
        return minCost
    }
}


public extension WeightedGraph where V: Hashable, W: Comparable & Numeric  {
        
    /// Computes the minimum-cost spanning arborescence of the graph, starting from the specified root.
    ///
    /// - The algorithm does not modify the graph object it is called on, and will return a new graph object that only contains the vertices reachable
    ///   from the specified root, and the edges that constitute the MSA.
    ///
    /// - Note: It is not guaranteed that the indices of vertices in the result graph are the same as the original graph. Though,
    ///  the references of vertices are the same (no copy or cloning of any vertex is performed). Specifically, if all the vertices of the original graph
    ///  were reachable from `root`, then the indices of all vertices are preserved, otherwise they're altered to accomodate for the underlying
    ///  implementation of Gabow's algorithm.
    ///
    /// - Parameter root: The index of the vertex in `self.vertices` that will be the root of the MSA.
    /// - Returns: A pair `(msa: WeightedGraph<V,W>, minCost: W)`, under the type of `MSAResult`, composed of a new graph
    /// that is the minimum cost spanning arborescence of the graph this method was called on, and the corresponding minimum cost.
    ///
    /// - Throws: `MSAError.graphFormatError(reason: String)`, if the graph this method is called on has at least one undirected edge.
    ///
    /// - Complexity: Time: O(E + V·log(V)), Space: O(E+V)
    func MSA(root: Int) throws -> MSAResult<V, W> {
        assert(root >= 0 && root < self.vertexCount)

        var reachable = Set<V>()
        var directMap = [V: Int].init()
        
        let _ = self.bfs(fromIndex: root) { vertex in
            reachable.insert(vertex)
            return false
        }
        
        if reachable.count != self.vertexCount {
            assert(reachable.contains(self.vertices[root])) // O(1)
            
            let reachableGraph = WeightedGraph<V, W>()

            reachable.enumerated().forEach { i, vertex in
                directMap[vertex] = i
                let _ = reachableGraph.addVertex(vertex)
            }
            
            self.edgeList().forEach { edge in
                if reachable.contains(self.vertices[edge.u]) && reachable.contains(self.vertices[edge.v]) {
                    guard let u = directMap[self.vertices[edge.u]],
                          let v = directMap[self.vertices[edge.v]] else { fatalError() }
                    
                    reachableGraph.addEdge(
                        fromIndex: u,
                        toIndex: v,
                        weight: edge.weight,
                        directed: true
                    )
                }
            }
            
            return try reachableGraph.MSA(root: directMap[self.vertices[root]]!)
        } else {
            let gabow = Gabow<W>(verticesCount: self.vertexCount)
            
            try self.edgeList().forEach { edge in
                if !edge.directed {
                    throw MSAError.graphFormatError(reason: "Graph must be directed")
                }
                            
                gabow.createEdge(edge.u, edge.v, edge.weight)
            }
            
            let msa = gabow.run(root: root)
            let edges = gabow.reconstruct(root: root)
            
            let msaGraph = WeightedGraph<V, W>(vertices: self.vertices)

            let allEdges = self.edgeList()
            edges.forEach { edgeID in
                assert(edgeID >= 0 && edgeID < allEdges.count)
                
                let newEdge = allEdges[edgeID]
                msaGraph.addEdge(newEdge, directed: true)
            }
            
            assert(msaGraph.edgeList().count == self.vertexCount - 1)
            
            return MSAResult(
                arborescence: msaGraph,
                minCost: msa
            )
        }
    }
    
}

public enum MSAError: Error {
    case graphFormatError(reason: String)
}
