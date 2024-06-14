import Foundation

extension Double: HasMaximum {
    public static func maxValue() -> Double {
        return Double.infinity
    }
}
