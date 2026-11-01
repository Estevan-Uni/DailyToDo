import Foundation
import XCTest

/// Run against the independent Xcode UI-test host only. Each test gets a new
/// database namespace; no production app, notification authorization or login
/// registration is part of this suite.
final class DailyToDoUITests: XCTestCase {
    private let bundleID = "local.tododesktop.xcuitest"

    @MainActor private func launch(arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments = ["--ui-test=xcui-\(UUID().uuidString)"] + arguments + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-floatingCard", "NO", "-showCard", "YES"]
        app.launchEnvironment["TZ"] = "Asia/Shanghai"
        app.launch()
        let welcome = app.buttons["welcome-start"]
        if welcome.waitForExistence(timeout: 3) { welcome.click() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["main"].buttons["new-item"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func element(_ root: XCUIElement, _ identifier: String) -> XCUIElement {
        let value = root.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 8), "Missing \(identifier)")
        return value
    }
    @MainActor private func replace(_ control: XCUIElement, with text: String, app: XCUIApplication) {
        control.click(); app.typeKey("a", modifierFlags: .command); control.typeText(text)
    }
    @MainActor private func absent(_ control: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    @MainActor private func value(_ control: XCUIElement, equals text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    @MainActor private func selected(_ control: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true OR value == 1 OR value == '1'"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    @MainActor private func card(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(identifier: "desktop-card").firstMatch
        // Bring the ordinary panel in front of the main window before input.
        if card.exists { app.windows["main"].buttons["desktop-card-toggle"].click() }
        app.windows["main"].buttons["desktop-card-toggle"].click()
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        return card
    }
    @MainActor private func selectCategory(_ editor: XCUIElement, app: XCUIApplication) {
        element(editor, "editor-category").click()
        let choices = element(app, "category-options")
        // The isolated fixture has the four built-in types. Native Home/End
        // scroll a macOS list; arrows update its selection.
        for _ in 0..<3 { app.typeKey(.upArrow, modifierFlags: []) }
        let general = choices.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "通用")).firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 8)); selected(general)
        app.typeKey(.return, modifierFlags: [])
        absent(choices); value(element(editor, "editor-category"), equals: "通用")
    }
    @MainActor private func prepareTask(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.windows["main"].buttons["new-item"].click()
        let editor = element(app, "main-editor")
        replace(element(editor, "editor-title"), with: title, app: app)
        replace(element(editor, "editor-time"), with: "18:20", app: app)
        selectCategory(editor, app: app)
        return editor
    }
    @MainActor private func saveAndClose(_ editor: XCUIElement) {
        element(editor, "editor-save").click()
        absent(editor.buttons["editor-save-continue"])
        // Saving disables the button until the transaction and refresh finish.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element(editor, "editor-close"))
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        element(editor, "editor-close").click(); absent(editor)
    }
    @MainActor private func event(_ root: XCUIElement, prefix: String, title: String) -> XCUIElement {
        root.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, title)).firstMatch
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testCalendarScalesAndBlankDateOpenTheRightEditor() {
        let app = launch(); defer { app.terminate() }
        let main = app.windows["main"]
        main.radioButtons["周"].click(); selected(main.radioButtons["周"])
        main.radioButtons["月"].click(); selected(main.radioButtons["月"])
        main.buttons["new-item"].click()
        let editor = element(app, "main-editor"), date = element(editor, "editor-date").value as? String
        XCTAssertNotNil(date)
        element(editor, "editor-close").click(); absent(editor)
        guard let date else { return }
        main.buttons["calendar-day-\(date)-add"].click()
        let opened = element(app, "main-editor")
        value(element(opened, "editor-date"), equals: date)
        XCTAssertTrue(element(opened, "editor-time").exists && element(opened, "editor-category").exists)
        attach(app, "Calendar and conditional editor")
    }
    @MainActor func testValidationAndContinuousEntryPreserveVisibleDefaults() {
        let app = launch(); defer { app.terminate() }
        app.windows["main"].buttons["new-item"].click()
        let editor = element(app, "main-editor")
        element(editor, "editor-save").click()
        XCTAssertTrue(app.staticTexts["请填写事项或事件。"].waitForExistence(timeout: 8))
        replace(element(editor, "editor-title"), with: "连续录入第一项", app: app)
        selectCategory(editor, app: app)
        element(editor, "editor-save").click()
        XCTAssertTrue(app.staticTexts["请填写时间（00:00–23:59）。"].waitForExistence(timeout: 8))
        replace(element(editor, "editor-time"), with: "18:20", app: app)
        let date = element(editor, "editor-date").value as? String
        element(editor, "editor-save-continue").click()
        let next = element(app, "main-editor")
        value(element(next, "editor-title"), equals: "")
        value(element(next, "editor-time"), equals: "18:20")
        if let date { value(element(next, "editor-date"), equals: date) }
        value(element(next, "editor-category"), equals: "通用")
        XCTAssertTrue(event(app.windows["main"], prefix: "calendar-event-", title: "连续录入第一项").waitForExistence(timeout: 8))
        attach(app, "Continuous entry defaults")
    }
    @MainActor func testCompletionKeepsCalendarHistoryAndUndoRestoresTheCard() {
        let app = launch(); defer { app.terminate() }
        let editor = prepareTask("卡片完成与撤销", app: app); saveAndClose(editor)
        let card = card(app), complete = card.buttons["完成：卡片完成与撤销"]
        XCTAssertTrue(complete.waitForExistence(timeout: 8)); complete.click(); absent(complete)
        XCTAssertTrue(app.windows["main"].buttons["取消完成：卡片完成与撤销"].waitForExistence(timeout: 8))
        let history = event(app.windows["main"], prefix: "calendar-event-", title: "卡片完成与撤销")
        XCTAssertTrue(history.label.contains("已完成"))
        if card.buttons["card-undo"].exists { card.buttons["card-undo"].click() }
        else { app.typeKey("z", modifierFlags: [.command, .option]) }
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        XCTAssertTrue(app.windows["main"].buttons["完成：卡片完成与撤销"].waitForExistence(timeout: 8))
        attach(app, "Card undo and calendar history")
    }
    @MainActor func testCountdownCanBeEditedOnTheCardAndUpdatesTheApp() {
        let app = launch(); defer { app.terminate() }
        app.typeKey("n", modifierFlags: [.command, .shift])
        let editor = element(app, "main-editor")
        replace(element(editor, "editor-title"), with: "期待的日子", app: app)
        replace(element(editor, "editor-date"), with: "2099-01-15", app: app)
        saveAndClose(editor)
        // macOS native sidebar rows expose their label, not identifiers on the
        // SwiftUI Label inside the row. Scope the exact label to the main window.
        let navigation = app.windows["main"].descendants(matching: .any).matching(NSPredicate(format: "label == %@", "倒计时")).firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 8)); navigation.click()
        XCTAssertTrue(event(app.windows["main"], prefix: "countdown-event-", title: "期待的日子").waitForExistence(timeout: 8))
        let card = card(app), tile = event(card, prefix: "card-countdown-", title: "期待的日子")
        XCTAssertTrue(tile.waitForExistence(timeout: 8)); tile.click()
        let cardEditor = element(app, "card-editor")
        replace(element(cardEditor, "editor-title"), with: "更期待的日子", app: app)
        replace(element(cardEditor, "editor-date"), with: "2099-02-16", app: app)
        element(cardEditor, "editor-save").click(); absent(cardEditor)
        let changed = event(app.windows["main"], prefix: "countdown-event-", title: "更期待的日子")
        XCTAssertTrue(changed.waitForExistence(timeout: 8)); XCTAssertTrue(changed.label.contains("2099-02-16"))
        attach(app, "Countdown edit shared across windows")
    }
    @MainActor func testDiscardingTheMainWindowDraftDoesNotBringItBack() {
        let app = launch(); defer { app.terminate() }
        let card = card(app)
        card.buttons["card-open-main"].click()
        app.windows["main"].buttons["new-item"].click()
        let editor = element(app, "main-editor")
        replace(element(editor, "editor-title"), with: "明确放弃的草稿", app: app)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["不保存"].waitForExistence(timeout: 8)); app.buttons["不保存"].click()
        absent(app.windows["main"])
        card.buttons["card-open-main"].click()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 8)); absent(editor)
        app.windows["main"].buttons["new-item"].click()
        value(element(element(app, "main-editor"), "editor-title"), equals: "")
    }
    @MainActor func testDailyOccurrencesCompleteIndependently() {
        let app = launch(); defer { app.terminate() }
        let editor = prepareTask("每日固定安排", app: app)
        element(editor, "editor-repeat").click(); app.menuItems["每日"].click()
        XCTAssertTrue(element(editor, "recurrence-preview").exists)
        saveAndClose(editor)
        let card = card(app), complete = card.buttons["完成：每日固定安排"]
        XCTAssertTrue(complete.waitForExistence(timeout: 8)); complete.click(); absent(complete)
        card.buttons["card-next-day"].click()
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        card.buttons["card-previous-day"].click(); absent(complete)
        XCTAssertTrue(app.windows["main"].buttons["取消完成：每日固定安排"].waitForExistence(timeout: 8))
        attach(app, "Independent daily occurrences")
    }
    @MainActor func testCategoryKeyboardCommitsOnlyItsChoiceAndEscapeKeepsDraft() {
        let app = launch(); defer { app.terminate() }
        let editor = prepareTask("类型键盘选择", app: app)
        let chooser = element(editor, "editor-category")
        chooser.click(); _ = element(app, "category-options")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        value(chooser, equals: "工作")
        XCTAssertTrue(editor.buttons["editor-save-continue"].exists)
        XCTAssertFalse(event(app.windows["main"], prefix: "calendar-event-", title: "类型键盘选择").exists)
        chooser.click(); _ = element(app, "category-options")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        value(chooser, equals: "工作"); value(element(editor, "editor-title"), equals: "类型键盘选择")
        chooser.click(); _ = element(app, "category-options")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        value(chooser, equals: "生活")
        app.typeKey(.return, modifierFlags: .command)
        absent(editor.buttons["editor-save-continue"])
        XCTAssertTrue(event(app.windows["main"], prefix: "calendar-event-", title: "类型键盘选择").waitForExistence(timeout: 8))
        attach(app, "Category keyboard choice and explicit save")
    }
    @MainActor func testMinimumCardPreservesTwoPanesAndFixedAddControls() {
        for dark in [false, true] {
            let options = ["--ui-demo", "--ui-stress", "--ui-minimum-card", dark ? "--ui-dark" : "--ui-light"]
            let app = launch(arguments: options); defer { app.terminate() }
            let card = card(app)
            XCTAssertEqual(card.frame.width, 600, accuracy: 1)
            XCTAssertEqual(card.frame.height, 340, accuracy: 1)
            let left = card.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-tasks-")).firstMatch
            let right = element(card, "card-countdowns")
            XCTAssertTrue(left.waitForExistence(timeout: 8))
            XCTAssertLessThan(left.frame.minX, right.frame.minX)
            XCTAssertEqual(left.frame.width, right.frame.width, accuracy: 2)
            XCTAssertGreaterThan(left.frame.height, 60); XCTAssertGreaterThan(right.frame.height, 60)
            XCTAssertTrue(card.buttons["card-add-task"].isHittable && card.buttons["card-add-countdown"].isHittable)
            attach(app, dark ? "Minimum card dark" : "Minimum card light")
        }
    }
}
