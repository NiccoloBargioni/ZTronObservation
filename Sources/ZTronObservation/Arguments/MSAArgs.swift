import Foundation

open class MSAArgs: BroadcastArgs, @unchecked Sendable {
    private let from: any Component
    private let fromLock = DispatchSemaphore(value: 1)

    public init(root: any Component, from: any Component) {
        self.from = from
        super.init(source: root)
    }
    
    public func getFrom() -> any Component {
        fromLock.wait()
        
        defer {
            fromLock.signal()
        }
        
        return self.from
    }
    
    public func getRoot() -> any Component {
        return super.getSource()
    }
}
