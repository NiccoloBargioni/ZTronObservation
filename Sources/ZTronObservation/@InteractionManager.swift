import Foundation

@propertyWrapper public final class InteractionsManaging {
    var setupOr: OnRegisterConflict
    var detachOr: OnUnregisterConflict
    
    public var wrappedValue: (any MSAInteractionsManager)? {
        didSet {
            guard let wrappedValue = self.wrappedValue else { return }
            wrappedValue.setup(or: self.setupOr)
        }
        
        willSet {
            guard let wrappedValue = self.wrappedValue else { return }
            wrappedValue.detach(or: self.detachOr)
        }
    }

    public init(wrappedValue: (any MSAInteractionsManager)?, setupOr: OnRegisterConflict = .ignore, detachOr: OnUnregisterConflict = .fail) {
        self.wrappedValue = wrappedValue
        self.setupOr = setupOr
        self.detachOr = detachOr
    }
}
