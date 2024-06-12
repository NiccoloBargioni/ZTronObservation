import Foundation

internal extension CGFloat {
    func toFloat() -> Float {
        return Float(self)
    }
    
    func toDouble() -> Double {
        return Double(self)
    }
    
    func toInt() -> Int {
        return Int(self)
    }
    
    func toString() -> String {
        return "\(self)"
    }
}
