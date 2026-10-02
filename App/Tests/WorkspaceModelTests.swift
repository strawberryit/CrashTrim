import AppKit
import SwiftUI
import XCTest

final class WorkspaceModelTests: XCTestCase {
    @MainActor
    func testPasteProcessCopyAndClear() async throws {
        let clipboard = MemoryClipboard()
        clipboard.text = "Serial Number: TEST-PRIVATE-SERIAL\nKeep this diagnostic"
        let model = WorkspaceModel(clipboard: clipboard)
        model.paste()
        XCTAssertTrue(model.input.contains("TEST-PRIVATE-SERIAL"))
        model.additionalStrings = "diagnostic"
        model.process()
        try await waitForProcessing(model)
        let result = try XCTUnwrap(model.result)
        XCTAssertFalse(result.output.contains("TEST-PRIVATE-SERIAL"))
        XCTAssertFalse(result.output.contains("diagnostic"))
        model.copyResult()
        XCTAssertEqual(clipboard.text, result.output)
        XCTAssertTrue(model.copied)
        model.clear()
        XCTAssertEqual(model.input, "")
        XCTAssertEqual(model.additionalStrings, "")
        XCTAssertNil(model.result)
        XCTAssertFalse(model.copied)
        XCTAssertFalse(model.canProcess)
        // Clear affects only app memory, not an intentionally copied result.
        XCTAssertEqual(clipboard.text, result.output)
    }

    @MainActor
    func testSystemClipboardAdapterUsingPrivatePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CrashTrimTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: pasteboard)
        guard clipboard.writeText("Synthetic clipboard test") else {
            throw XCTSkip("현재 실행 환경에서 시스템 클립보드 서비스에 접근할 수 없습니다.")
        }
        XCTAssertEqual(clipboard.readText(), "Synthetic clipboard test")
    }

    @MainActor
    func testFailedCopyReportsAnErrorWithoutMarkingCopied() async throws {
        let clipboard = MemoryClipboard()
        clipboard.acceptWrites = false
        let model = WorkspaceModel(clipboard: clipboard)
        model.input = "Keep diagnostic"
        model.process()
        try await waitForProcessing(model)
        model.copyResult()
        XCTAssertFalse(model.copied)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNotNil(model.result)
    }

    @MainActor
    func testEditingInputOrRulesInvalidatesCopyableResult() async throws {
        let model = WorkspaceModel()
        model.input = "Useful diagnostic"
        model.process()
        try await waitForProcessing(model)
        XCTAssertNotNil(model.result)
        model.additionalStrings = "Useful"
        XCTAssertNil(model.result)
        model.process()
        try await waitForProcessing(model)
        XCTAssertNotNil(model.result)
        model.input = "Changed input"
        XCTAssertNil(model.result)
    }

    @MainActor
    func testClearingOrEditingDuringProcessingRejectsStaleResults() async throws {
        let model = WorkspaceModel()
        model.input = String(repeating: "Serial Number: PRIVATE-TEST-991\n", count: 20_000)
        model.process()
        XCTAssertTrue(model.isProcessing)
        model.clear()
        model.input = "New input"
        model.process()
        try await waitForProcessing(model)
        XCTAssertEqual(model.result?.output, "New input")
        // Let the cancelled predecessor attempt to finish; it must not overwrite.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.result?.output, "New input")
    }

    @MainActor
    func testTextViewUsesPlainTextAndDisablesSystemSubstitutions() {
        let editor = LogTextView(text: .constant(""), editable: false, accessibilityLabel: "결과")
        let coordinator = editor.makeCoordinator()
        // Exercise the actual AppKit configuration via a shared constructor.
        let scroll = LogTextView.makeScrollView(coordinator: coordinator, editable: false, accessibilityLabel: "결과")
        let textView = scroll.documentView as? NSTextView
        XCTAssertEqual(textView?.isEditable, false)
        XCTAssertEqual(textView?.isSelectable, true)
        XCTAssertEqual(textView?.isRichText, false)
        XCTAssertEqual(textView?.isContinuousSpellCheckingEnabled, false)
        XCTAssertEqual(textView?.isAutomaticTextReplacementEnabled, false)
        XCTAssertEqual(textView?.isAutomaticQuoteSubstitutionEnabled, false)
        scroll.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        scroll.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(textView?.frame.width ?? 0, scroll.contentSize.width)
        XCTAssertGreaterThanOrEqual(textView?.frame.height ?? 0, scroll.contentSize.height)
    }

    @MainActor
    private func waitForProcessing(_ model: WorkspaceModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isProcessing && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isProcessing, "Processing timed out")
        XCTAssertNil(model.errorMessage)
    }
}

@MainActor
private final class MemoryClipboard: Clipboard {
    var text: String?
    var acceptWrites = true
    func readText() -> String? { text }
    func writeText(_ text: String) -> Bool {
        guard acceptWrites else { return false }
        self.text = text
        return true
    }
}
