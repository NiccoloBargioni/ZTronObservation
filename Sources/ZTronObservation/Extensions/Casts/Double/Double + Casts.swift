import Foundation

internal extension Double {
    func toFloat() -> Float {
        return Float(self)
    }
    
    func toInt() -> Int {
        return Int(self)
    }
    
    func toCGFloat() -> CGFloat {
        return CGFloat(self)
    }
    
    func toString(specifier: String?) -> String {
        return "\(self)"
    }
}
