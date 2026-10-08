import Foundation
import CoreGraphics

nonisolated enum LauncherTourLayout {
    static func cardCenter(in size: CGSize, target: CGRect?, cardWidth: CGFloat) -> CGPoint {
        guard let target else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let toRight = target.midX < size.width / 2
        let desiredX = toRight ? target.maxX + cardWidth / 2 + 56 : target.minX - cardWidth / 2 - 56
        let horizontalMargin = min(cardWidth / 2 + 24, size.width / 2)
        let verticalMargin = min(210, size.height / 2)
        return CGPoint(x: min(max(desiredX, horizontalMargin), size.width - horizontalMargin),
                       y: min(max(target.midY, verticalMargin), size.height - verticalMargin))
    }
}
