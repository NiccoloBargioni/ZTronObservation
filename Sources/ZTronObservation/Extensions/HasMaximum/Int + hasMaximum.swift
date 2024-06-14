import Foundation

extension Int: HasMaximum {
    public static func maxValue() -> Int {
        return (Self.max)/2
    }
}
