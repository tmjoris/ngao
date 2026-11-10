import XCTest

/// Walks the main screens and attaches a screenshot of each for the README.
@MainActor
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        await MainActor.run {
            app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func enter(pin: String) {
        for digit in pin { app.buttons["pin-key-\(digit)"].tap() }
    }

    private func send(to phone: String, amount: String) {
        app.cells["send-money"].tap()
        app.textFields["destination-primary"].tap()
        app.textFields["destination-primary"].typeText(phone)
        app.textFields["amount"].tap()
        app.textFields["amount"].typeText(amount)
    }

    func testWalkthrough() {
        XCTAssertTrue(app.buttons["pin-key-delete"].waitForExistence(timeout: 5))
        snap("01-login")

        enter(pin: "000000")
        let status = app.staticTexts["login-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        sleep(1)
        snap("02-wrong-pin")

        enter(pin: "739142")
        XCTAssertTrue(app.staticTexts["balance-0110012345678"].firstMatch.waitForExistence(timeout: 5))
        snap("03-home")

        send(to: "0712345678", amount: "2500")
        snap("04-send-money")
        app.buttons["continue"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        snap("05-confirm")
        app.alerts.buttons["Send"].firstMatch.tap()
        let headline = app.staticTexts["status-headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        sleep(1)
        snap("06-sent")
        app.buttons["status-action"].tap()

        XCTAssertTrue(app.cells["send-money"].waitForExistence(timeout: 5))
        send(to: "0712345699", amount: "1000")
        app.buttons["continue"].tap()
        app.alerts.buttons["Send"].firstMatch.tap()
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        sleep(1)
        snap("07-unknown")
        app.buttons["status-secondary"].tap()

        XCTAssertTrue(app.cells["cards"].waitForExistence(timeout: 5))
        snap("08-home-history")
        app.cells["cards"].tap()
        XCTAssertTrue(app.switches["freeze-card-1"].waitForExistence(timeout: 5))
        app.switches["freeze-card-1"].tap()
        sleep(1)
        snap("09-cards")
    }
}
