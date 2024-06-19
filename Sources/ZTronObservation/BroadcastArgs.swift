import Foundation

/// A class representing the informations to attach to each notification. This implementation simply stores a reference
/// to the component that originated the notification. Can be extended to include informations about what changed.
open class BroadcastArgs {
    private let source: any Component
    
    init(source: any Component) {
        self.source = source
    }
    
    public final func getSource() -> any Component {
        return self.source
    }
}
