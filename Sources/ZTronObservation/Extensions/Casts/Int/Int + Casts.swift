import Foundation

internal extension Int {
    func toFloat() -> Float {
        return Float(self)
    }
    
    func toDouble() -> Double {
        return Double(self)
    }
    
    func toCGFloat() -> CGFloat {
        return CGFloat(self)
    }
    
    func toString() -> String {
        return "\(self)"
    }
}
