import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformTextView = UITextView
#else
import AppKit
typealias PlatformTextView = NSTextView
#endif

/// Bridges the UITextView / NSTextView back to the `[RichRun]` model: pushes
/// edits into the binding, reports focus, and applies selection formatting.
@MainActor
final class RichTextCoordinator: NSObject {
    private var runs: Binding<[RichRun]>
    var config: RichTextConfig
    var onPlainChange: (String) -> Void
    weak var textView: PlatformTextView?
    /// True while the user is mid-edit, so external syncs don't stomp the cursor.
    private(set) var isEditingText = false
    private var placeholderLabel: PlatformLabel?
    #if os(macOS)
    /// Floating Bold/Italic/Color popover shown above a Mac text selection.
    var formatPopover: NSPopover?
    /// The selection captured when the popover opened, so formatting applies to
    /// it even after focus/selection changes while clicking the popover.
    var savedPopoverSelection: NSRange?
    #endif

    init(runs: Binding<[RichRun]>, config: RichTextConfig,
         onPlainChange: @escaping (String) -> Void) {
        self.runs = runs
        self.config = config
        self.onPlainChange = onPlainChange
    }

    // MARK: - Model <-> view

    func setRuns(_ runs: [RichRun]) {
        guard let tv = textView, let storage = tv.storageOpt else { return }
        let attr = RichTextConverter.attributed(runs, baseFont: config.baseFont,
                                                baseColor: config.baseColor)
        if storage.string != attr.string {
            storage.setAttributedString(attr)
            tv.typingAttributes = baseTypingAttributes()
        }
        updatePlaceholderVisibility()
    }

    private func pushModel() {
        guard let storage = textView?.storageOpt else { return }
        // Pass the base color so default text isn't recorded as an explicit hex
        // (which baked dark-mode white into runs and made styled words look like
        // they reverted to no style when a note was reopened).
        let newRuns = RichTextConverter.runs(from: storage, baseColor: config.baseColor)
        runs.wrappedValue = newRuns
        onPlainChange(storage.string)
    }

    /// Updates only the runs binding — no onPlainChange call. Used when applying
    /// formatting so the plain-text smart() handler never sees a trailing newline
    /// that NSTextView appends to rich-text storage and misreads as an Enter key
    /// press (which would insert a phantom empty block).
    private func pushRuns() {
        guard let storage = textView?.storageOpt else { return }
        runs.wrappedValue = RichTextConverter.runs(from: storage, baseColor: config.baseColor)
    }

    private func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        [.font: config.baseFont, .foregroundColor: config.baseColor]
    }

    // MARK: - Formatting (operates on the current selection)

    func handle(_ command: RichFormatCommand, overrideRange: NSRange? = nil) {
        guard let tv = textView, let storage = tv.storageOpt else { return }
        let range = overrideRange ?? selectedRange(tv)
        switch command {
        case .bold:   toggleTrait(bold: true, in: range, storage: storage, tv: tv)
        case .italic: toggleTrait(bold: false, in: range, storage: storage, tv: tv)
        case .color(let hex): setColor(hex, in: range, storage: storage, tv: tv)
        }
        pushRuns()
    }

    private func toggleTrait(bold: Bool, in range: NSRange,
                             storage: NSTextStorage, tv: PlatformTextView) {
        // Decide whether to add or remove based on the run at the selection start.
        let probe = range.length > 0 ? range.location : max(0, range.location - 1)
        let currentlyOn = traitActive(bold: bold, at: probe, storage: storage, tv: tv)
        let add = !currentlyOn

        func restyle(_ font: PlatformFont) -> PlatformFont {
            if bold { return add ? font.withBold() : font.withoutBold() }
            return add ? font.withItalic() : font.withoutItalic()
        }

        if range.length == 0 {
            // No selection: change typing attributes for the next characters.
            var attrs = tv.typingAttributes
            let font = (attrs[.font] as? PlatformFont) ?? config.baseFont
            attrs[.font] = restyle(font)
            tv.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? PlatformFont) ?? config.baseFont
            storage.addAttribute(.font, value: restyle(font), range: sub)
        }
        storage.endEditing()
    }

    private func setColor(_ hex: String?, in range: NSRange,
                          storage: NSTextStorage, tv: PlatformTextView) {
        let color = hex.flatMap { Color(hex: $0) }.map { PlatformColor($0) } ?? config.baseColor
        if range.length == 0 {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = color
            tv.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: color, range: range)
        storage.endEditing()
    }

    private func traitActive(bold: Bool, at index: Int,
                             storage: NSTextStorage, tv: PlatformTextView) -> Bool {
        let font: PlatformFont
        if storage.length == 0 || index >= storage.length {
            font = (tv.typingAttributes[.font] as? PlatformFont) ?? config.baseFont
        } else {
            font = (storage.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont) ?? config.baseFont
        }
        let traits = font.fontDescriptor.symbolicTraits
        #if os(iOS)
        return bold ? traits.contains(.traitBold) : traits.contains(.traitItalic)
        #else
        return bold ? traits.contains(.bold) : traits.contains(.italic)
        #endif
    }

    private func selectedRange(_ tv: PlatformTextView) -> NSRange {
        #if os(iOS)
        return tv.selectedRange
        #else
        return tv.selectedRange()
        #endif
    }

    // MARK: - Placeholder

    func refreshPlaceholder(_ text: String) {
        guard let tv = textView else { return }
        if placeholderLabel == nil {
            let label = PlatformLabel()
            configurePlaceholder(label, on: tv)
            placeholderLabel = label
        }
        setPlaceholderText(text)
        updatePlaceholderVisibility()
    }

    private func updatePlaceholderVisibility() {
        let empty = (textView?.storageOpt?.length ?? 0) == 0
        placeholderLabel?.isHidden = !empty
    }
}

extension PlatformTextView {
    /// Uniform optional access to the text storage across UIKit / AppKit.
    var storageOpt: NSTextStorage? { textStorage }
}

// MARK: - Delegate conformance

#if os(iOS)
extension RichTextCoordinator: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        RichTextActive.shared.handler = { [weak self] in self?.handle($0) }
    }
    func textViewDidEndEditing(_ textView: UITextView) {
        if RichTextActive.shared.handler != nil { RichTextActive.shared.handler = nil }
    }
    func textViewDidChange(_ textView: UITextView) {
        isEditingText = true
        updatePlaceholderVisibility()
        textView.invalidateIntrinsicContentSize()
        pushModel()
        isEditingText = false
    }

    /// A UIKit formatting bar shown above the keyboard (the SwiftUI keyboard
    /// toolbar only appears for SwiftUI focusables, which a UITextView isn't).
    func makeAccessoryBar() -> UIToolbar {
        let bar = UIToolbar()
        bar.sizeToFit()
        let bold = UIBarButtonItem(image: UIImage(systemName: "bold"),
                                   style: .plain, target: self, action: #selector(barBold))
        let italic = UIBarButtonItem(image: UIImage(systemName: "italic"),
                                     style: .plain, target: self, action: #selector(barItalic))
        let colorActions = [UIAction(title: "Default") { [weak self] _ in self?.handle(.color(nil)) }]
            + BlockTextColor.allCases.map { c in
                UIAction(title: c.name) { [weak self] _ in self?.handle(.color(c.hex)) }
            }
        let color = UIBarButtonItem(image: UIImage(systemName: "paintpalette"),
                                    menu: UIMenu(title: "Text Color", children: colorActions))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(barDone))
        bar.items = [bold, italic, color, flex, done]
        return bar
    }

    @objc private func barBold()   { handle(.bold) }
    @objc private func barItalic() { handle(.italic) }
    @objc private func barDone()   { textView?.resignFirstResponder() }
}

private typealias PlatformLabel = UILabel
private extension RichTextCoordinator {
    func configurePlaceholder(_ label: UILabel, on tv: UITextView) {
        label.font = config.baseFont
        label.textColor = .placeholderText
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: tv.topAnchor),
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor),
        ])
    }
    func setPlaceholderText(_ text: String) { placeholderLabel?.text = text }
}
#else
extension RichTextCoordinator: NSTextViewDelegate {
    func textDidBeginEditing(_ notification: Notification) {
        RichTextActive.shared.handler = { [weak self] in self?.handle($0) }
    }
    func textDidEndEditing(_ notification: Notification) {
        if RichTextActive.shared.handler != nil { RichTextActive.shared.handler = nil }
        // Do NOT close the format popover here — this fires when the popover
        // itself becomes key (stealing focus), which would immediately close
        // the popover we just opened.
    }
    func textDidChange(_ notification: Notification) {
        isEditingText = true
        updatePlaceholderVisibility()
        textView?.invalidateIntrinsicContentSize()
        pushModel()
        isEditingText = false
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = textView as? NSTextView else { return }
        let sel = tv.selectedRange()
        if sel.length > 0 {
            savedPopoverSelection = sel
            showFormatPopover(in: tv, selection: sel)
        } else if savedPopoverSelection == nil {
            // Real deselect (not a side-effect of clicking the popover).
            formatPopover?.close()
        }
    }
}

// MARK: - Floating format popover (Mac)
extension RichTextCoordinator {
    /// Called by the popover buttons. Applies the format to the range that was
    /// active when the popover opened — bypassing the text view's current
    /// selection so focus/responder changes can't corrupt the target range.
    func handleFromPopover(_ command: RichFormatCommand) {
        let saved = savedPopoverSelection
        savedPopoverSelection = nil
        handle(command, overrideRange: saved)
        // Collapse the selection BEFORE closing so that when focus returns to the
        // text view, textViewDidChangeSelection fires with length=0 and doesn't
        // immediately reopen the popover.
        if let tv = textView as? NSTextView, let r = saved {
            tv.setSelectedRange(NSRange(location: r.location + r.length, length: 0))
        }
        formatPopover?.close()
    }

    func showFormatPopover(in tv: NSTextView, selection: NSRange) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        rect = rect.offsetBy(dx: tv.textContainerInset.width, dy: tv.textContainerInset.height)

        if formatPopover == nil {
            let pop = NSPopover()
            pop.behavior = .semitransient
            pop.animates = false
            pop.delegate = self
            let content = FormatPopoverContent { [weak self] cmd in
                self?.handleFromPopover(cmd)
            }
            pop.contentViewController = NSHostingController(rootView: content)
            pop.contentSize = NSSize(width: 200, height: 36)
            formatPopover = pop
        }
        guard let pop = formatPopover else { return }
        // Already visible — don't reposition on every drag event (causes flicker).
        if pop.isShown { return }
        pop.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
    }
}

extension RichTextCoordinator: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        savedPopoverSelection = nil
    }
}

private typealias PlatformLabel = NSTextField
private extension RichTextCoordinator {
    func configurePlaceholder(_ label: NSTextField, on tv: NSTextView) {
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = config.baseFont
        label.textColor = .placeholderTextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: tv.topAnchor),
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
        ])
    }
    func setPlaceholderText(_ text: String) { placeholderLabel?.stringValue = text }
}
#endif

// MARK: - Font trait removal

extension PlatformFont {
    func withoutBold() -> PlatformFont {
        #if os(iOS)
        return removingTrait(.traitBold)
        #else
        return removingTrait(.bold)
        #endif
    }
    func withoutItalic() -> PlatformFont {
        #if os(iOS)
        return removingTrait(.traitItalic)
        #else
        return removingTrait(.italic)
        #endif
    }
    #if os(iOS)
    private func removingTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> PlatformFont {
        var traits = fontDescriptor.symbolicTraits
        traits.remove(trait)
        guard let desc = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return PlatformFont(descriptor: desc, size: pointSize)
    }
    #else
    private func removingTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> PlatformFont {
        var traits = fontDescriptor.symbolicTraits
        traits.remove(trait)
        let desc = fontDescriptor.withSymbolicTraits(traits)
        return PlatformFont(descriptor: desc, size: pointSize) ?? self
    }
    #endif
}
