import Foundation
import CoreGraphics
import Testing
@testable import Arclume

struct LauncherTourLayoutTests {
    @Test func absentTargetUsesWindowCenter() {
        #expect(LauncherTourLayout.cardCenter(in: CGSize(width: 1200, height: 720), target: nil, cardWidth: 360)
            == CGPoint(x: 600, y: 360))
    }
    @Test func toolbarAndBottomTargetsKeepGuideOnscreen() {
        for rect in [CGRect(x: 1140, y: 12, width: 42, height: 42),
                     CGRect(x: 14, y: 650, width: 74, height: 40),
                     CGRect(x: 800, y: 640, width: 330, height: 48)] {
            let center = LauncherTourLayout.cardCenter(in: CGSize(width: 1200, height: 720), target: rect, cardWidth: 360)
            #expect(center.x >= 204 && center.x <= 996)
            #expect(center.y >= 210 && center.y <= 510)
        }
    }
    @Test func smallWindowNeverProducesNegativeCenter() {
        let center = LauncherTourLayout.cardCenter(in: CGSize(width: 300, height: 300),
            target: CGRect(x: 290, y: 0, width: 10, height: 10), cardWidth: 280)
        #expect(center == CGPoint(x: 150, y: 150))
    }
}
