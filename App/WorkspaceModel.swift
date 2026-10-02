import AppKit
import SwiftUI
import CrashTrimCore

@MainActor
protocol Clipboard {
    func readText() -> String?
    func writeText(_ text: String) -> Bool
}

@MainActor
struct SystemClipboard: Clipboard {
    var pasteboard: NSPasteboard = .general
    func readText() -> String? { pasteboard.string(forType: .string) }
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { invalidate() } } }
    @Published var additionalStrings = "" { didSet { if additionalStrings != oldValue { invalidate() } } }
    @Published private(set) var result: ProcessingResult?
    @Published private(set) var isProcessing = false
    @Published private(set) var copied = false
    @Published private(set) var errorMessage: String?

    private var revision = UUID()
    private var worker: Task<ProcessingResult, Error>?
    private let clipboard: any Clipboard

    init(clipboard: any Clipboard = SystemClipboard()) { self.clipboard = clipboard }

    var canProcess: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing }

    private func invalidate() {
        revision = UUID()
        worker?.cancel()
        worker = nil
        result = nil
        copied = false
        errorMessage = nil
        isProcessing = false
    }

    func paste() {
        if let string = clipboard.readText() { input = string }
    }

    func clear() {
        input = ""
        additionalStrings = ""
        invalidate()
    }

    func process() {
        guard canProcess else { return }
        let source = input
        let additions = additionalStrings
        let request = revision
        result = nil
        errorMessage = nil
        copied = false
        isProcessing = true
        let task = Task.detached(priority: .userInitiated) {
            try ReportProcessor.process(source, additionalStrings: additions)
        }
        worker = task
        Task { [weak self] in
            do {
                let processed = try await task.value
                guard let self, self.revision == request else { return }
                self.result = processed
                self.isProcessing = false
                self.worker = nil
            } catch {
                guard let self, self.revision == request else { return }
                self.isProcessing = false
                self.worker = nil
                if !(error is CancellationError) { self.errorMessage = "처리하지 못했습니다. 입력을 확인한 뒤 다시 시도해 주세요." }
            }
        }
    }

    func copyResult() {
        guard let result else { return }
        copied = clipboard.writeText(result.output)
        errorMessage = copied ? nil : "클립보드에 복사하지 못했습니다. 결과에서 텍스트를 선택해 복사해 주세요."
    }
}
