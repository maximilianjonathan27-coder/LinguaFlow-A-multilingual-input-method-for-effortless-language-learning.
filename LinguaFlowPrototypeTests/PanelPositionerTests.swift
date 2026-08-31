import CoreGraphics
import LinguaFlowCore
import XCTest

final class PanelPositionerTests: XCTestCase {
    private let panelSize = CGSize(width: 430, height: 218)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPanelAppearsBelowCaretWhenSpaceAllows() {
        let anchor = CGRect(x: 200, y: 600, width: 2, height: 20)
        let frame = PanelPositioner.frame(anchor: anchor, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(frame.origin.x, 200)
        XCTAssertEqual(frame.origin.y, 374)
    }

    func testPanelFlipsAboveCaretNearBottom() {
        let anchor = CGRect(x: 200, y: 40, width: 2, height: 20)
        let frame = PanelPositioner.frame(anchor: anchor, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(frame.origin.y, 68)
    }

    func testPanelClampsToRightAndTopEdges() {
        let anchor = CGRect(x: 1350, y: 860, width: 2, height: 20)
        let frame = PanelPositioner.frame(anchor: anchor, panelSize: panelSize, visibleFrame: screen)

        XCTAssertEqual(frame.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
    }
}
