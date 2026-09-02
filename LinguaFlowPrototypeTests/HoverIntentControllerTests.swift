import LinguaFlowCore
import XCTest

@MainActor
final class HoverIntentControllerTests: XCTestCase {
    func testHoverThresholdAndOneCardAtATime() async {
        let controller = HoverIntentController(hoverDelay: 0.05, dismissDelay: 0.025)
        var shown: [String] = []
        controller.onIntent = { shown.append($0) }
        controller.pointerEnteredTranslation("conference")
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertTrue(shown.isEmpty)
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(shown, ["conference"])
        controller.pointerEnteredTranslation("meeting")
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(shown, ["conference", "meeting"])
        XCTAssertEqual(controller.state, .visible("meeting"))
    }

    func testExitBeforeThresholdCancels() async {
        let controller = HoverIntentController(hoverDelay: 0.05)
        var didShow = false
        controller.onIntent = { _ in didShow = true }
        controller.pointerEnteredTranslation("conference")
        try? await Task.sleep(for: .milliseconds(20))
        controller.pointerExitedTranslation()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(didShow)
        XCTAssertEqual(controller.state, .idle)
    }

    func testCardEntryCancelsDismissGracePeriod() async {
        let controller = HoverIntentController(hoverDelay: 0.01, dismissDelay: 0.05)
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }
        controller.pointerEnteredTranslation("conference")
        try? await Task.sleep(for: .milliseconds(20))
        controller.pointerExitedTranslation()
        try? await Task.sleep(for: .milliseconds(20))
        controller.pointerEnteredCard()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(dismissals, 0)
        controller.pointerExitedCard()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(dismissals, 1)
    }

    func testTranslationExitDismissesAfterGracePeriod() async {
        let controller = HoverIntentController(hoverDelay: 0.01, dismissDelay: 0.03)
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }

        controller.pointerEnteredTranslation("conference")
        try? await Task.sleep(for: .milliseconds(20))
        controller.pointerExitedTranslation()
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    func testCardExitDismissesAfterDelayEvenIfTranslationTrackingIsStillActive() async {
        let controller = HoverIntentController(hoverDelay: 0.01, dismissDelay: 0.05)
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }

        controller.pointerEnteredTranslation("meeting")
        try? await Task.sleep(for: .milliseconds(20))
        controller.pointerEnteredCard()
        controller.pointerExitedCard()
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    func testImmediateDismissAlwaysClosesEvenWhenStateIsIdle() {
        let controller = HoverIntentController()
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }

        controller.dismissImmediately()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(controller.state, .idle)
    }
}
