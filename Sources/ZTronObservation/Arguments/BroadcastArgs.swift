import Foundation

/// A class representing the informations to attach to each notification. This implementation simply stores a reference
/// to the component that originated the notification. Can be extended to include informations about what changed.
open class BroadcastArgs: @unchecked Sendable {
    private let source: any Component
    private let sourceLock = DispatchSemaphore(value: 1)
    
    public init(source: any Component) {
        self.source = source
    }
    
    public func getSource() -> any Component {
        self.sourceLock.wait()
        
        defer {
            self.sourceLock.signal()
        }
        
        return self.source
    }
}
