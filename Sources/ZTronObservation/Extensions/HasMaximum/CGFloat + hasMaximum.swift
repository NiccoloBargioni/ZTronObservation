import Foundation

extension CGFloat: HasMaximum {
    public static func maxValue() -> CGFloat {
        return CGFloat.infinity
    }
}
