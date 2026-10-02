import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator, editable: editable, accessibilityLabel: accessibilityLabel)
    }

    static func makeScrollView(coordinator: Coordinator, editable: Bool, accessibilityLabel: String) -> NSScrollView {
        let scroll = LogScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .textBackgroundColor
        scroll.drawsBackground = true
        let view = NSTextView(frame: .zero)
        view.delegate = coordinator
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isRichText = false
        view.isEditable = editable
        view.isSelectable = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel(accessibilityLabel)
        scroll.documentView = view
        return scroll
    }

    private final class LogScrollView: NSScrollView {
        override func layout() {
            super.layout()
            guard let view = documentView as? NSTextView else { return }
            let size = contentSize
            if view.minSize != size { view.minSize = size }
            let requiredSize = NSSize(width: max(view.frame.width, size.width), height: max(view.frame.height, size.height))
            if view.frame.size != requiredSize { view.setFrameSize(requiredSize) }
        }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = editable
        if view.string != text {
            context.coordinator.isUpdating = true
            view.string = text
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.scrollToBeginningOfDocument(nil)
            context.coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isUpdating = false
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
