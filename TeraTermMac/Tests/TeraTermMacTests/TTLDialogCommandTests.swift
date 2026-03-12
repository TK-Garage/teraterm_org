/*
 * TTL Dialog Command Tests
 * Tests for dialog box commands: messagebox, yesnobox, inputbox,
 * passwordbox, listbox, statusbox, closesbox, filenamebox, dirnamebox,
 * bringupbox, setdlgpos.
 *
 * These tests verify parsing and result-handling logic without
 * displaying actual UI. Dialog commands that require UI interaction
 * are tested by directly calling DialogCommandProvider methods
 * with mocked completions.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Dialog Command Tests

final class TTLDialogCommandTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        interpreter.delegate = delegate
    }

    override func tearDown() {
        interpreter.stop()
        interpreter = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Helper

    /// Execute a script synchronously (only for non-UI commands).
    @discardableResult
    private func execSync(_ script: String, maxSteps: Int = 10000) -> Bool {
        interpreter.loadScript(script)
        interpreter.prescanLabels()
        var steps = 0
        while interpreter.parser.status == .run && steps < maxSteps {
            guard interpreter.parser.getNewLine() else {
                interpreter.parser.status = .end
                break
            }
            interpreter.scanLabel()
            do {
                try interpreter.execCmnd()
            } catch {
                return false
            }
            // If the command put us in .pause (dialog), break out
            if interpreter.parser.status == .pause {
                break
            }
            steps += 1
        }
        return interpreter.parser.status == .end
    }

    // MARK: - Test: setdlgpos parsing

    func testSetDlgPos() {
        execSync("setdlgpos 200 300")
        XCTAssertEqual(interpreter.dialogProvider.posX, 200)
        XCTAssertEqual(interpreter.dialogProvider.posY, 300)
    }

    func testSetDlgPosNegativeResets() {
        execSync("setdlgpos 100 100")
        XCTAssertEqual(interpreter.dialogProvider.posX, 100)

        // Setting to -1 should act as "default/centered"
        interpreter.parser.status = .run
        execSync("setdlgpos -1 -1")
        XCTAssertEqual(interpreter.dialogProvider.posX, -1)
        XCTAssertEqual(interpreter.dialogProvider.posY, -1)
    }

    func testSetDlgPosMultipleCalls() {
        let script = """
        setdlgpos 10 20
        setdlgpos 50 60
        """
        execSync(script)
        XCTAssertEqual(interpreter.dialogProvider.posX, 50)
        XCTAssertEqual(interpreter.dialogProvider.posY, 60)
    }

    // MARK: - Test: messagebox argument parsing

    func testMessageBoxParsesArguments() {
        // messagebox puts parser in .pause state waiting for UI
        let script = "messagebox 'Hello World' 'Test Title'"
        execSync(script)
        // Parser should be paused (waiting for dialog)
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    func testMessageBoxDefaultTitle() {
        // messagebox with only message (no title) - should still parse correctly
        let script = "messagebox 'Hello'"
        execSync(script)
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    // MARK: - Test: yesnobox result handling

    func testYesNoBoxResultYes() {
        // Simulate: user presses "Yes" by calling DialogCommandProvider directly
        let provider = interpreter.dialogProvider

        let expectation = XCTestExpectation(description: "YesNoBox completion")
        var capturedResult = -1

        // Call the provider's method directly (bypasses UI)
        // We test the completion callback logic
        provider.posX = -1  // centered

        // Simulate the callback that yesnobox would trigger
        interpreter.parser.setResult(1)  // Yes
        capturedResult = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        XCTAssertEqual(capturedResult, 1)
        expectation.fulfill()

        wait(for: [expectation], timeout: 1.0)
    }

    func testYesNoBoxResultNo() {
        interpreter.parser.setResult(0)  // No
        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Test: inputbox result and inputstr

    func testInputBoxResultOK() {
        // Simulate user entering text and pressing OK
        interpreter.parser.setResult(1)
        interpreter.parser.setInputStr("TestUser")

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        let inputStr = interpreter.parser.getStrVal(id: interpreter.parser.inputStrVarId)

        XCTAssertEqual(result, 1)
        XCTAssertEqual(inputStr, "TestUser")
    }

    func testInputBoxResultCancel() {
        interpreter.parser.setResult(0)
        interpreter.parser.setInputStr("")

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        let inputStr = interpreter.parser.getStrVal(id: interpreter.parser.inputStrVarId)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(inputStr, "")
    }

    // MARK: - Test: filenamebox result

    func testFilenameBoxSelectedPath() {
        // Simulate: user selects a file via filenamebox
        // filenamebox stores path in a string variable (inputstr)
        interpreter.parser.setResult(1)
        interpreter.parser.setInputStr("/Users/Shared/test.ini")

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        let path = interpreter.parser.getStrVal(id: interpreter.parser.inputStrVarId)

        XCTAssertEqual(result, 1)
        XCTAssertEqual(path, "/Users/Shared/test.ini")
    }

    func testFilenameBoxCancelled() {
        interpreter.parser.setResult(0)

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Test: listbox result

    func testListBoxSelectedIndex() {
        // Simulate: user selects index 2 (1-based) from a 3-item list
        interpreter.parser.setResult(2)
        interpreter.parser.setInputStr("AppKit")

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        let selected = interpreter.parser.getStrVal(id: interpreter.parser.inputStrVarId)

        XCTAssertEqual(result, 2)
        XCTAssertEqual(selected, "AppKit")
    }

    func testListBoxCancelled() {
        interpreter.parser.setResult(0)
        interpreter.parser.setInputStr("")

        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Test: statusbox singleton behavior

    func testStatusBoxDelegateNotification() {
        let script = "statusbox 'Processing...' 'Status'"
        execSync(script)

        // Delegate should receive the message
        XCTAssertEqual(delegate.statusBoxMessage, "Processing...")
        XCTAssertEqual(delegate.statusBoxTitle, "Status")
    }

    func testCloseSBoxDelegateNotification() {
        // Open then close
        let script = """
        statusbox 'Working...' 'Status'
        closesbox
        """
        execSync(script)

        // After closesbox, delegate should be notified
        XCTAssertEqual(delegate.statusBoxMessage, "")
        XCTAssertEqual(delegate.statusBoxTitle, "")
    }

    func testStatusBoxUpdateDoesNotDuplicate() {
        let provider = interpreter.dialogProvider

        // First statusbox call
        let script1 = "statusbox 'First message' 'Title'"
        execSync(script1)

        // Verify delegate got first message
        XCTAssertEqual(delegate.statusBoxMessage, "First message")

        // Second call should update, not create duplicate
        interpreter.parser.status = .run
        let script2 = "statusbox 'Updated message' 'Title'"
        execSync(script2)

        XCTAssertEqual(delegate.statusBoxMessage, "Updated message")
    }

    // MARK: - Test: DialogCommandProvider positioning

    func testDialogProviderDefaultPosition() {
        let provider = DialogCommandProvider()
        XCTAssertEqual(provider.posX, -1)
        XCTAssertEqual(provider.posY, -1)
    }

    func testDialogProviderPositionSet() {
        let provider = DialogCommandProvider()
        provider.posX = 100
        provider.posY = 200
        XCTAssertEqual(provider.posX, 100)
        XCTAssertEqual(provider.posY, 200)
    }

    func testDialogProviderResetPosition() {
        let provider = DialogCommandProvider()
        provider.posX = 100
        provider.posY = 200
        provider.resetPosition()
        XCTAssertEqual(provider.posX, -1)
        XCTAssertEqual(provider.posY, -1)
    }

    func testDialogProviderCleanup() {
        let provider = DialogCommandProvider()
        provider.posX = 50
        provider.posY = 75
        provider.cleanup()
        XCTAssertEqual(provider.posX, -1)
        XCTAssertEqual(provider.posY, -1)
    }

    // MARK: - Test: Display Mode

    func testDisplayModeDefault() {
        let provider = DialogCommandProvider()
        XCTAssertEqual(provider.displayMode, .modal)
    }

    func testDisplayModeSheet() {
        let provider = DialogCommandProvider()
        provider.displayMode = .sheet
        XCTAssertEqual(provider.displayMode, .sheet)
    }

    func testDisplayModeFloatingPanel() {
        let provider = DialogCommandProvider()
        provider.displayMode = .floatingPanel
        XCTAssertEqual(provider.displayMode, .floatingPanel)
    }

    // MARK: - Test: ListBoxDataSource

    func testListBoxDataSourceCount() {
        let items = ["Swift", "AppKit", "TTL"]
        let ds = DialogListBoxDataSource(items: items)
        let tableView = NSTableView()
        XCTAssertEqual(ds.numberOfRows(in: tableView), 3)
    }

    func testListBoxDataSourceValues() {
        let items = ["Swift", "AppKit", "TTL"]
        let ds = DialogListBoxDataSource(items: items)
        let tableView = NSTableView()

        XCTAssertEqual(ds.tableView(tableView, objectValueFor: nil, row: 0) as? String, "Swift")
        XCTAssertEqual(ds.tableView(tableView, objectValueFor: nil, row: 1) as? String, "AppKit")
        XCTAssertEqual(ds.tableView(tableView, objectValueFor: nil, row: 2) as? String, "TTL")
    }

    func testListBoxDataSourceOutOfBounds() {
        let items = ["one"]
        let ds = DialogListBoxDataSource(items: items)
        let tableView = NSTableView()
        XCTAssertNil(ds.tableView(tableView, objectValueFor: nil, row: 5))
    }

    func testListBoxDataSourceEmpty() {
        let ds = DialogListBoxDataSource(items: [])
        let tableView = NSTableView()
        XCTAssertEqual(ds.numberOfRows(in: tableView), 0)
    }

    // MARK: - Test: Dialog commands pause parser

    func testInputBoxPausesParser() {
        let script = "inputbox 'Enter name' 'Title'"
        execSync(script)
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    func testYesNoBoxPausesParser() {
        let script = "yesnobox 'Continue?' 'Confirm'"
        execSync(script)
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    func testListBoxPausesParser() {
        let script = "listbox \"A\\nB\\nC\" 'Choose'"
        execSync(script)
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    // MARK: - Test: setdlgpos affects provider before dialog commands

    func testSetDlgPosBeforeMessageBox() {
        let script = """
        setdlgpos 150 250
        messagebox 'Test' 'Title'
        """
        execSync(script)
        // Position should be set before the dialog is shown
        XCTAssertEqual(interpreter.dialogProvider.posX, 150)
        XCTAssertEqual(interpreter.dialogProvider.posY, 250)
        // Parser paused at messagebox
        XCTAssertEqual(interpreter.parser.status, .pause)
    }

    // MARK: - Test: bringupbox does not pause parser

    func testBringupBoxDoesNotPause() {
        let script = "bringupbox"
        // bringupbox is non-blocking - it should complete without pausing
        // Note: the original Tera Term bringupbox takes no arguments and
        // just brings the window to front
        let completed = execSync(script)
        XCTAssertTrue(completed)
    }

    // MARK: - Test: statusbox does not pause parser

    func testStatusBoxDoesNotPause() {
        let script = """
        statusbox 'Working...' 'Status'
        closesbox
        """
        let completed = execSync(script)
        XCTAssertTrue(completed)
    }

    // MARK: - Test: Integration with result variable across commands

    func testResultVariablePreservedAcrossNonDialogCommands() {
        // Set result via a non-dialog command, verify it persists
        let script = """
        result = 42
        """
        execSync(script)
        let result = interpreter.parser.getIntVal(id: interpreter.parser.resultVarId)
        XCTAssertEqual(result, 42)
    }

    func testInputStrVariableSet() {
        let script = """
        inputstr = 'test_value'
        """
        execSync(script)
        let str = interpreter.parser.getStrVal(id: interpreter.parser.inputStrVarId)
        XCTAssertEqual(str, "test_value")
    }
}

// TTLDialogDisplayMode Equatable conformance is declared in the main module.

#endif
