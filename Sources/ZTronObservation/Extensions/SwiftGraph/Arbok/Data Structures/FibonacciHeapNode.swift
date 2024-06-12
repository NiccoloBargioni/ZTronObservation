import Foundation

internal final class FibonacciHeapNode: Hashable {
    static func == (lhs: FibonacciHeapNode, rhs: FibonacciHeapNode) -> Bool {
        return lhs.from == rhs.from && lhs.to == rhs.to && lhs.weight == rhs.weight && lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(from)
        hasher.combine(to)
        hasher.combine(weight)
        hasher.combine(id)
    }
    
    internal var from: Int
    internal var to: Int
    internal var weight: Int
    internal var id: Int
    
    internal var parent: FibonacciHeapNode? = nil
    internal var children: LinkedList = LinkedList<FibonacciHeapNode>()
    internal var isLoser: Bool = false
    internal var list_it: LinkedList<FibonacciHeapNode>.LinkedListIndex?
    
    init(from: Int, to: Int, weight: Int, id: Int) {
        self.from = from
        self.to = to
        self.weight = weight
        self.id = id
    }
    
    internal func dumpToFile() {
        print("\(id): \(from) --\(weight)--> \(to), loser? \(isLoser)", to: &logging)
        
        if let parent = parent {
            print("Parent: ", to: &logging)
            print("\(parent.id): \(parent.from) --\(parent.weight)--> \(parent.to), loser? \(parent.isLoser)", to: &logging)
        } else {
            print("Parent: nil", to: &logging)
        }
        
        print("Children: [", to: &logging)
        
        self.children.forEach { child in
            print("\(child.id): \(child.from) --\(child.weight)--> \(child.to), loser? \(child.isLoser)", to: &logging)
        }
        
        print("]", to: &logging)
    }
}


extension FibonacciHeapNode: CustomStringConvertible {
    var description: String {
        return "[\(from) ---\(weight)---> \(to)]"
    }
}
