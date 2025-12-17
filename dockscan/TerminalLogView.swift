#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class TerminalLogBuffer: ObservableObject {
    private(set) var attributedText = NSMutableAttributedString()
    private let maxChars: Int

    init(maxChars: Int = 250_000) {
        self.maxChars = maxChars
    }

    func clear() {
        attributedText = NSMutableAttributedString()
        objectWillChange.send()
    }

    func append(service: String, line: String) {
        let attributedLine = TerminalLogHighlighter.render(service: service, line: line)
        attributedText.append(attributedLine)

        if attributedText.length > maxChars {
            let overflow = attributedText.length - maxChars
            attributedText.deleteCharacters(in: NSRange(location: 0, length: overflow))
        }

        objectWillChange.send()
    }
}

private enum TerminalLogHighlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let prefixFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    private static let servicePalette: [NSColor] = [
        .systemTeal, .systemBlue, .systemPurple, .systemPink, .systemOrange,
        .systemGreen, .systemYellow, .systemIndigo, .systemRed, .systemBrown
    ]

    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"(\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?\b|\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b)"#,
        options: []
    )

    private static let levelRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(trace|debug|info|warn(?:ing)?|error|fatal|panic)\b"#,
        options: []
    )

    private static let httpStatusRegex = try? NSRegularExpression(
        pattern: #"\b([1-5]\d{2})\b"#,
        options: []
    )

    static func render(service: String, line: String) -> NSAttributedString {
        let prefix = "[\(service)] "
        let combined = prefix + line + "\n"

        let result = NSMutableAttributedString(
            string: combined,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ]
        )

        let prefixRange = NSRange(location: 0, length: (prefix as NSString).length)
        result.addAttributes(
            [
                .font: prefixFont,
                .foregroundColor: color(forService: service)
            ],
            range: prefixRange
        )

        let messageStart = prefixRange.length
        let messageLength = (combined as NSString).length - messageStart
        guard messageLength > 0 else { return result }
        let messageRange = NSRange(location: messageStart, length: messageLength)

        if let timestampRegex {
            for match in timestampRegex.matches(in: combined, options: [], range: messageRange) {
                result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
            }
        }

        if let levelRegex {
            for match in levelRegex.matches(in: combined, options: [], range: messageRange) {
                let level = ((combined as NSString).substring(with: match.range) as NSString).lowercased
                let color: NSColor = switch level {
                case "error", "fatal", "panic": .systemRed
                case "warn", "warning": .systemOrange
                case "info": .systemBlue
                case "debug", "trace": .tertiaryLabelColor
                default: .labelColor
                }
                result.addAttributes([.foregroundColor: color, .font: prefixFont], range: match.range)
            }
        }

        if let httpStatusRegex {
            for match in httpStatusRegex.matches(in: combined, options: [], range: messageRange) {
                guard match.numberOfRanges >= 2 else { continue }
                let code = Int((combined as NSString).substring(with: match.range(at: 1))) ?? 0
                let color: NSColor = switch code {
                case 200..<300: .systemGreen
                case 300..<400: .systemTeal
                case 400..<600: .systemRed
                default: .secondaryLabelColor
                }
                result.addAttribute(.foregroundColor, value: color, range: match.range(at: 1))
            }
        }

        return result
    }

    private static func color(forService service: String) -> NSColor {
        let idx = abs(service.hashValue) % servicePalette.count
        return servicePalette[idx]
    }
}

struct TerminalLogTextView: NSViewRepresentable {
    @ObservedObject var buffer: TerminalLogBuffer
    @Binding var autoScroll: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.lastLength = 0
        textView.textStorage?.setAttributedString(buffer.attributedText)
        context.coordinator.lastLength = buffer.attributedText.length
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let newLength = buffer.attributedText.length
        let oldLength = context.coordinator.lastLength

        if newLength < oldLength {
            textView.textStorage?.setAttributedString(buffer.attributedText)
        } else if newLength > oldLength {
            let deltaRange = NSRange(location: oldLength, length: newLength - oldLength)
            let delta = buffer.attributedText.attributedSubstring(from: deltaRange)
            textView.textStorage?.append(delta)
        }

        context.coordinator.lastLength = newLength

        if autoScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }

    final class Coordinator {
        var textView: NSTextView?
        var lastLength: Int = 0
    }
}
#endif
