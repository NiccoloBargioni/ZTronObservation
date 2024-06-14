import Foundation

extension Float: HasMaximum {
    public static func maxValue() -> Float {
        return Float.infinity
    }
}
