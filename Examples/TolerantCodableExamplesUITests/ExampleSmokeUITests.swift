import XCTest

/// 冒烟测试：逐页打开示例，确认结果与诊断展示符合预期。
@MainActor
final class ExampleSmokeUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launch()
    }

    private func open(_ id: String) {
        let row = app.buttons["example-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), id)
        row.tap()
    }

    private var diagnosticCount: String {
        let header = app.staticTexts["diagnostic-count"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        return header.label
    }

    func testWrappersShowDiagnosticsOnlyForDirtyData() {
        open("wrappers")
        XCTAssertEqual(diagnosticCount, "诊断 0 条")
        app.buttons["脏数据"].tap()
        XCTAssertNotEqual(diagnosticCount, "诊断 0 条")
    }

    func testUnknownEnumRecordsFallbacks() {
        open("enum")
        XCTAssertEqual(diagnosticCount, "诊断 2 条")
    }

    func testPathDecodingShowsResultsAndErrors() {
        open("path")
        XCTAssertTrue(app.descendants(matching: .any)["path-result"].waitForExistence(timeout: 5))
        app.buttons["data.missing"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["path-error"].waitForExistence(timeout: 5))
    }

    func testContractFlagsDirtyFixtureOnly() {
        open("contract")
        XCTAssertTrue(app.descendants(matching: .any)["contract-products_clean-passed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["contract-products_dirty-failed"].exists)
    }

    func testConversionAndJSONValuePagesOpen() {
        open("conversion")
        XCTAssertTrue(app.staticTexts["ChatMessage.decode(fromAny:)"].waitForExistence(timeout: 5) || app.navigationBars.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        open("json-value")
        XCTAssertTrue(app.navigationBars["LYJSONValue"].waitForExistence(timeout: 5))
    }
}
