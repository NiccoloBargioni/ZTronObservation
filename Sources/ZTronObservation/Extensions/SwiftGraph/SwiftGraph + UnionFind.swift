internal class UnionFind<T: Hashable> {
    private var parent: [T: T]
    private var rank: [T: Int]

    init(elements: [T]) {
        self.parent = [:]
        self.rank = [:]
        self.makeSet(elements)
    }

    private final func makeSet(_ elements: [T]) {
        for element in elements {
            parent[element] = element
            rank[element] = 0
        }
    }

    func find(_ x: T) -> T {
        if parent[x] != x {
            parent[x] = find(parent[x]!) // Path compression
        }
        
        return parent[x]!
    }

    func union(_ x: T, _ y: T) {
        let xRoot = find(x)
        let yRoot = find(y)
        
        if xRoot == yRoot {
            return
        }
        
        if rank[xRoot]! < rank[yRoot]! {
            parent[xRoot] = yRoot
        } else if rank[xRoot]! > rank[yRoot]! {
            parent[yRoot] = xRoot
        } else {
            parent[yRoot] = xRoot
            rank[xRoot]! += 1
        }
    }
    
    internal func getRank() -> [T: Int] {
        return self.rank
    }
    
    internal func getParent() -> [T: T] {
        return self.parent
    }
}
