import XCTest

final class DualAgentEndToEndUITests: XCTestCase {
    private let hermesURL = "http://127.0.0.1:8787"

    func testLocalOpenClawSetupCodePairing() throws {
        let setupCode = ProcessInfo.processInfo.environment["OPENCLAW_SETUP_CODE"] ?? ""
        XCTAssertFalse(setupCode.isEmpty, "OPENCLAW_SETUP_CODE must be supplied at runtime")

        let app = XCUIApplication()
        app.launch()

        let openClawSegment = app.buttons["OpenClaw"]
        XCTAssertTrue(openClawSegment.waitForExistence(timeout: 8))
        openClawSegment.tap()

        let pair = app.buttons["openclaw.pairQR"]
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        pair.tap()

        let code = app.textFields["openclaw.setupCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        code.tap()
        code.typeText(setupCode)
        app.buttons["openclaw.applySetupCode"].tap()

        let sessions = app.navigationBars["Sessions"]
        if !sessions.waitForExistence(timeout: 25) {
            XCTFail("OpenClaw pairing did not reach Sessions. UI hierarchy:\n\(app.debugDescription)")
        }
    }

    func testRealHermesChatByTypingAndReturn() throws {
        let password = ProcessInfo.processInfo.environment["HERMES_WEBUI_PASSWORD"] ?? ""
        XCTAssertFalse(password.isEmpty, "HERMES_WEBUI_PASSWORD must be supplied at runtime")

        let app = XCUIApplication()
        app.launchEnvironment["DA_DEFAULT_HERMES_URL"] = hermesURL
        app.launch()

        let server = app.textFields["onboarding.serverURL"]
        XCTAssertTrue(server.waitForExistence(timeout: 8))
        server.tap()
        server.typeText(String(repeating: "\u{8}", count: 80))
        server.typeText(hermesURL)

        let credential = app.secureTextFields["onboarding.credential"]
        XCTAssertTrue(credential.waitForExistence(timeout: 4))
        credential.tap()
        credential.typeText(password)

        let connect = app.buttons["onboarding.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 4))
        connect.tap()
        XCTAssertTrue(app.navigationBars["Sessions"].waitForExistence(timeout: 15))

        let newSession = app.buttons["sessions.new"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        newSession.tap()

        let model = app.textFields["newSession.model"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        model.typeText(String(repeating: "\u{8}", count: 80))
        model.typeText("@minimax:MiniMax-M3")

        let create = app.buttons["newSession.create"]
        XCTAssertTrue(create.isEnabled)
        create.tap()

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        rows.firstMatch.tap()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Please reply with exactly: UI-E2E-OK")
        let sendKey = app.keyboards.buttons.matching(
            NSPredicate(format: "label ==[c] 'send' OR identifier ==[c] 'send'")
        ).firstMatch
        XCTAssertTrue(sendKey.waitForExistence(timeout: 5))
        sendKey.tap()

        let userMessage = app.descendants(matching: .any)["chat.message.user"]
        XCTAssertTrue(userMessage.waitForExistence(timeout: 8))
        let assistant = app.descendants(matching: .any)["chat.message.assistant"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 90))
        XCTAssertFalse(((assistant.label).trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty)
    }
}
