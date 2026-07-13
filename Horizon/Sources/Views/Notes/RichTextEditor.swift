import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A format command applied to the currently-focused rich editor's selection.
enum RichFormatCommand {
    case bold, italic, color(String?)
}

/// Tracks the focused rich-text editor so menus / bars can act on its current
/// selection without threading a controller through the view tree.
@MainActor
final class RichTextActive {
    static let shared = RichTextActive()
    var handler: ((RichFormatCommand) -> Void)?
    func apply(_ command: RichFormatCommand) { handler?(command) }
}

/// Visual configuration for a rich editor, derived from the block type.
struct RichTextConfig {
    var fontSize: CGFloat = 16
    var weight: Font.Weight = .regular
    var monospaced: Bool = false
    var baseColorHex: String? = nil

    var baseFont: PlatformFont {
        let w = weight.uiFontWeight
        #if os(iOS)
        return monospaced ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: w)
                          : UIFont.systemFont(ofSize: fontSize, weight: w)
        #else
        return monospaced ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: w)
                          : NSFont.systemFont(ofSize: fontSize, weight: w)
        #endif
    }

    var baseColor: PlatformColor {
        if let hex = baseColorHex, let c = Color(hex: hex) { return PlatformColor(c) }
        #if os(iOS)
        return .label
        #else
        return .labelColor
        #endif
    }
}

private extension Font.Weight {
    var uiFontWeight: PlatformFont.Weight {
        switch self {
        case .bold:     return .bold
        case .semibold: return .semibold
        case .medium:   return .medium
        case .heavy:    return .heavy
        case .light:    return .light
        default:        return .regular
        }
    }
}

/// SwiftUI wrapper over UITextView / NSTextView that edits `[RichRun]` with
/// inline bold / italic / color. Focus is driven by a plain `focusRequest`
/// binding (NOT `@FocusState`) — a UITextView/NSTextView isn't a SwiftUI
/// focusable, and bridging it through `@FocusState` made SwiftUI resign first
/// responder on every keystroke (the keyboard-dismiss bug).
struct RichTextEditor: View {
    @Binding var runs: [RichRun]
    let placeholder: String
    let config: RichTextConfig
    let blockID: UUID
    @Binding var focusRequest: UUID?
    let onPlainChange: (String) -> Void

    var body: some View {
        _RichTextEditor(runs: $runs, placeholder: placeholder, config: config,
                        blockID: blockID, focusRequest: $focusRequest,
                        onPlainChange: onPlainChange)
    }
}

#if os(iOS)
private struct _RichTextEditor: UIViewRepresentable {
    @Binding var runs: [RichRun]
    let placeholder: String
    let config: RichTextConfig
    let blockID: UUID
    @Binding var focusRequest: UUID?
    let onPlainChange: (String) -> Void

    func makeCoordinator() -> RichTextCoordinator {
        RichTextCoordinator(runs: $runs, config: config, onPlainChange: onPlainChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false                 // auto-grow inside the List
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        // Wrap text to the cell width instead of the longest line's intrinsic
        // width — otherwise the text view stretches past the Form cell and the
        // body is clipped on both sides (the centered, unreadable Notes bug).
        tv.textContainer.widthTracksTextView = true
        tv.font = config.baseFont
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.inputAccessoryView = context.coordinator.makeAccessoryBar()
        context.coordinator.textView = tv
        context.coordinator.setRuns(runs)
        context.coordinator.refreshPlaceholder(placeholder)
        return tv
    }

    /// Pin the editor to the width SwiftUI proposes (the Form cell width) and
    /// compute height by laying the text out at that width. Without this,
    /// SwiftUI uses the UITextView's intrinsic width (the longest line), which
    /// overflows the cell and clips the body left and right.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .greatestFiniteMagnitude
        else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.config = config
        context.coordinator.onPlainChange = onPlainChange
        if !context.coordinator.isEditingText {
            context.coordinator.setRuns(runs)
        }
        context.coordinator.refreshPlaceholder(placeholder)
        // Programmatic focus only — never resign here (that closed the keyboard).
        if focusRequest == blockID {
            if !tv.isFirstResponder { tv.becomeFirstResponder() }
            DispatchQueue.main.async { focusRequest = nil }
        }
    }
}
#else
private struct _RichTextEditor: NSViewRepresentable {
    @Binding var runs: [RichRun]
    let placeholder: String
    let config: RichTextConfig
    let blockID: UUID
    @Binding var focusRequest: UUID?
    let onPlainChange: (String) -> Void

    func makeCoordinator() -> RichTextCoordinator {
        RichTextCoordinator(runs: $runs, config: config, onPlainChange: onPlainChange)
    }

    func makeNSView(context: Context) -> NSTextView {
        let tv = AutoGrowTextView()
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.drawsBackground = false
        tv.font = config.baseFont
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.formatHandler = { [weak coordinator = context.coordinator] cmd in
            coordinator?.handle(cmd)
        }
        if let container = tv.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }
        context.coordinator.textView = tv
        context.coordinator.setRuns(runs)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        context.coordinator.config = config
        context.coordinator.onPlainChange = onPlainChange
        if !context.coordinator.isEditingText {
            context.coordinator.setRuns(runs)
        }
        tv.invalidateIntrinsicContentSize()
        if focusRequest == blockID {
            if tv.window?.firstResponder !== tv { tv.window?.makeFirstResponder(tv) }
            DispatchQueue.main.async { focusRequest = nil }
        }
    }
}

/// NSTextView that reports its laid-out height so SwiftUI sizes the row to fit,
/// and surfaces the rich-text format actions in its right-click menu.
final class AutoGrowTextView: NSTextView {
    var formatHandler: ((RichFormatCommand) -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        let height = lm.usedRect(for: tc).height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 20))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        let bold = NSMenuItem(title: "Bold", action: #selector(applyBoldRich), keyEquivalent: "")
        bold.target = self; menu.addItem(bold)
        let italic = NSMenuItem(title: "Italic", action: #selector(applyItalicRich), keyEquivalent: "")
        italic.target = self; menu.addItem(italic)

        let colorParent = NSMenuItem(title: "Text Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let def = NSMenuItem(title: "Default", action: #selector(applyColorRich(_:)), keyEquivalent: "")
        def.target = self; colorMenu.addItem(def)
        for c in BlockTextColor.allCases {
            let item = NSMenuItem(title: c.name, action: #selector(applyColorRich(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = c.hex; colorMenu.addItem(item)
        }
        colorParent.submenu = colorMenu
        menu.addItem(colorParent)
        return menu
    }

    @objc private func applyBoldRich()   { formatHandler?(.bold) }
    @objc private func applyItalicRich() { formatHandler?(.italic) }
    @objc private func applyColorRich(_ sender: NSMenuItem) {
        formatHandler?(.color(sender.representedObject as? String))
    }
}

/// Compact toolbar that floats above a text selection on Mac (like Notion):
/// Bold / Italic / Default / color swatches.
struct FormatPopoverContent: View {
    let onCommand: (RichFormatCommand) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { onCommand(.bold) } label: {
                Image(systemName: "bold").frame(width: 28, height: 28)
            }
            .help("Bold")
            Button { onCommand(.italic) } label: {
                Image(systemName: "italic").frame(width: 28, height: 28)
            }
            .help("Italic")
            Divider().frame(height: 18).padding(.horizontal, 2)
            Button { onCommand(.color(nil)) } label: {
                Image(systemName: "textformat").frame(width: 28, height: 28)
            }
            .help("Default color")
            ForEach(BlockTextColor.allCases, id: \.hex) { c in
                Button { onCommand(.color(c.hex)) } label: {
                    Circle().fill(Color(hex: c.hex) ?? .primary)
                        .frame(width: 12, height: 12).padding(8)
                }
                .help(c.name)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: 36)
    }
}
#endif
