import XCTest

@MainActor
final class ArclumeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        runID = UUID().uuidString
        app = XCUIApplication()
        app.launchEnvironment = ["ARCLUME_UI_TEST_FIXTURE": "1", "ARCLUME_TEST_RUN_ID": runID, "ARCLUME_UI_TEST_MODE": "standard"]
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    override func tearDownWithError() throws {
        app.terminate()
        let suite = "io.github.pigeonmuyz.arclume.tests." + runID
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        app = nil
    }

    private func launch(_ scenario: String = "library") {
        app.launchEnvironment["ARCLUME_UI_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts["arclume-test-isolated"].waitForExistence(timeout: 10))
    }

    func testFirstLaunchOffersArclumeModesAndSelectsStandard() {
        launch("onboarding")
        XCTAssertTrue(app.buttons["mode-card-standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-card-jx3"].exists)
        app.buttons["mode-card-standard"].click()
        XCTAssertTrue(app.staticTexts["fixture-selected-mode"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture-selected-mode"].label, "standard")
    }

    func testOwnedUninstalledGameHasSteamActionWithoutLaunchingSteam() {
        launch()
        let action = app.buttons["steam-install-action-720"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        // Never click installation/launch actions.
    }

    func testLibraryControlsAreReachable() {
        launch()
        for id in ["library-settings-button", "library-add-game-button", "library-open-steam-button"] {
            let button = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), id)
            XCTAssertTrue(button.isHittable, id)
        }
    }

    func testGraphicsUsesOneD3DMetalVersionSelector() {
        launch("graphics")
        let selector = app.descendants(matching: .any)["game-options-d3dmetal-version"].firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        XCTAssertTrue(selector.isHittable)
        XCTAssertFalse(app.checkBoxes["Metal 4 Backend"].exists)
        XCTAssertFalse(app.checkBoxes["GPTK4 beta 2"].exists)
        selector.click()
        XCTAssertTrue(app.menuItems["D3DMetal 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["DXVK"].exists)
        XCTAssertFalse(app.menuItems["DXMT"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
