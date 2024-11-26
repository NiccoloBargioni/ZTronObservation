import Foundation

public final class MSAArgs: BroadcastArgs, @unchecked Sendable {
    private var source: any Component {
        return payload.getSource()
    }
    private let from: any Component
    private let fromLock = DispatchSemaphore(value: 1)
    private let payload: BroadcastArgs

    public init(from: any Component, payload: BroadcastArgs) {
        self.payload = payload
        self.from = from
        super.init(source: payload.getSource())
    }
    
    public func getFrom() -> any Component {
        fromLock.wait()
        
        defer {
            fromLock.signal()
        }
        
        return self.from
    }
    
    public func getRoot() -> any Component {
        return super.getSource() // Already locked
    }
    
    override public func getSource() -> any Component {
        return self.getRoot()
    }
    
    public func getPayload() -> BroadcastArgs {
        return self.payload
    }
}
