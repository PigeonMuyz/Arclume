import SwiftUI

/// The same hit test drives the insertion marker and the committed order.
struct LauncherSidebarInsertion: Equatable {
    let target: String
    let after: Bool

    static func target(at point: CGPoint, source: String, frames: [String: CGRect]) -> Self? {
        guard let bounds = frames.values.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }),
              bounds.insetBy(dx: -12, dy: -10).contains(point),
              let row = frames.filter({ $0.key != source }).min(by: {
                  abs($0.value.midY - point.y) < abs($1.value.midY - point.y)
              }) else { return nil }
        return Self(target: row.key, after: point.y >= row.value.midY)
    }
}

struct LauncherSidebarDrag {
    let source: String
    let location: CGPoint
}

struct LauncherSidebarFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
