import SwiftGraph

internal extension Graph {
    /// Find a route from a vertex to the first that satisfies goalTest()
    /// using a breadth-first search.
    ///
    /// - parameter fromIndex: The index of the starting vertex.
    /// - parameter goalTest: Returns true if a given vertex is a goal.
    /// - returns: An array of Edges containing the entire route, or an empty array if no route could be found
    func ivBfs(fromIndex: Int, goalTest: (Int, V) -> Bool) -> [E] {
        // pretty standard bfs that doesn't visit anywhere twice; pathDict tracks route
        var visited: [Bool] = [Bool](repeating: false, count: vertexCount)
        let queue: Queue<Int> = Queue<Int>()
        var pathDict: [Int: Edge] = [Int: Edge]()
        queue.push(fromIndex)
        while !queue.isEmpty {
            let v: Int = queue.pop()
            if goalTest(v, vertexAtIndex(v)) {
                // figure out route of edges based on pathDict
                return pathDictToPath(from: fromIndex, to: v, pathDict: pathDict) as! [Self.E]
            }
            
            for e in edgesForIndex(v) {
                if !visited[e.v] {
                    visited[e.v] = true
                    queue.push(e.v)
                    pathDict[e.v] = e
                }
            }
        }
        return [] // no path found
    }
}
