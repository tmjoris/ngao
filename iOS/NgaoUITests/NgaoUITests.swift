import XCTest

/// Drives the real UI against the in-process scripted bank. PIN is 739142.
final class NgaoUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func enter(pin: String) {
        for digit in pin { app.buttons["pin-key-\(digit)"].tap() }
    }

    func testWrongPinShakesThenCorrectPinSignsIn() {
        enter(pin: "000000")
        let status = app.staticTexts["login-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertTrue(status.label.contains("Wrong PIN"))
        enter(pin: "739142")
        XCTAssertTrue(app.staticTexts["balance-0110012345678"].waitForExistence(timeout: 5))
    }

    func testSendMoneyToMpesaShowsReceipt() {
        enter(pin: "739142")
        XCTAssertTrue(app.cells["send-money"].waitForExistence(timeout: 5))
        app.cells["send-money"].tap()
        app.textFields["destination-primary"].tap()
        app.textFields["destination-primary"].typeText("0712345678")
        app.textFields["amount"].tap()
        app.textFields["amount"].typeText("2500")
        app.buttons["continue"].tap()
        app.alerts.buttons["Send"].tap()
        let headline = app.staticTexts["status-headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.label, "Sent")
        XCTAssertTrue(app.staticTexts["status-detail"].label.contains("Ref FT"))
        app.buttons["status-action"].tap()
        XCTAssertTrue(app.staticTexts["balance-0110012345678"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["balance-0110012345678"].label, "KES 181,987.00") // 184,520 - 2,500 - 33
    }

    func testLostResponseBlocksResendAndReconciles() {
        enter(pin: "739142")
        XCTAssertTrue(app.cells["send-money"].waitForExistence(timeout: 5))
        app.cells["send-money"].tap()
        app.textFields["destination-primary"].tap()
        app.textFields["destination-primary"].typeText("0712345699") // ..99 => bank commits, response lost
        app.textFields["amount"].tap()
        app.textFields["amount"].typeText("1000")
        app.buttons["continue"].tap()
        app.alerts.buttons["Send"].tap()
        let headline = app.staticTexts["status-headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertEqual(headline.label, "Confirming with the bank")
        XCTAssertTrue(app.staticTexts["status-detail"].label.contains("Do not send it again"))
        app.buttons["status-action"].tap() // Check now
        XCTAssertTrue(app.staticTexts["status-headline"].waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while app.staticTexts["status-headline"].label != "Sent" && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(app.staticTexts["status-headline"].label, "Sent")
    }

    func testSignOutReturnsToPin() {
        enter(pin: "739142")
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 5))
        app.buttons["sign-out"].tap()
        XCTAssertTrue(app.buttons["pin-key-delete"].waitForExistence(timeout: 3))
    }
}
