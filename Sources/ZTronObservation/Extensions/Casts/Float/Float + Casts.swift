import Foundation

internal extension Float {
    func toInt() -> Int {
        return Int(self)
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
