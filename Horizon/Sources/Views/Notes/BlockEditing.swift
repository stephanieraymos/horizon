import SwiftUI

/// Shared block-editing affordances for the Notion-style document editors
/// (Notes, Problems, task notes): a color palette, the right-click context
/// menu (Mac), and the floating formatting bar (iOS keyboard accessory).
///
/// Structural operations (insert above/below, duplicate, delete) are passed in
/// as closures so each host can splice its own `blocks` array; styling edits go
/// straight through the bound block.

// MARK: - Color palette

/// The Default + named-color buttons used by both the Text Color and the
/// Background submenus. Binds directly to a hex string column.
struct BlockColorButtons: View {
    @Binding var selection: String?
    var body: some View {
        Button { selection = nil } label: {
            Label("Default", systemImage: selection == nil ? "checkmark" : "circle")
        }
        ForEach(BlockTextColor.allCases) { c in
            Button { selection = c.hex } label: {
                Label(c.name, systemImage: selection == c.hex ? "checkmark.circle.fill" : "circle.fill")
            }
        }
    }
}

/// Color buttons that recolor the *current selection* of the focused rich
/// editor (inline), rather than the whole block.
struct InlineColorButtons: View {
    var body: some View {
        Button { RichTextActive.shared.apply(.color(nil)) } label: {
            Label("Default", systemImage: "circle")
        }
        ForEach(BlockTextColor.allCases) { c in
            Button { RichTextActive.shared.apply(.color(c.hex)) } label: {
                Label(c.name, systemImage: "circle.fill")
            }
        }
    }
}

// MARK: - Menu content (Mac context menu)

/// The full set of block actions, rendered as the body of a `.contextMenu`.
struct BlockMenuItems: View {
    @Binding var block: ContentBlock
    let onInsertAbove: (ContentBlockType) -> Void
    let onInsertBelow: (ContentBlockType) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private func setType(_ t: ContentBlockType) {
        block.type = t
        if t == .todo, block.checked == nil { block.checked = false }
    }

    var body: some View {
        Menu {
            ForEach(ContentBlockType.allCases) { t in
                Button(t.label, systemImage: t.icon) { onInsertBelow(t) }
            }
        } label: { Label("Add Block Below", systemImage: "arrow.down") }
        Menu {
            ForEach(ContentBlockType.allCases) { t in
                Button(t.label, systemImage: t.icon) { onInsertAbove(t) }
            }
        } label: { Label("Add Block Above", systemImage: "arrow.up") }

        Divider()

        Menu {
            ForEach(ContentBlockType.allCases) { t in
                Button(t.label, systemImage: t.icon) { setType(t) }
            }
        } label: { Label("Turn Into", systemImage: "arrow.triangle.2.circlepath") }

        if block.type.supportsTextStyle {
            Button { RichTextActive.shared.apply(.bold) } label: {
                Label("Bold", systemImage: "bold")
            }
            Button { RichTextActive.shared.apply(.italic) } label: {
                Label("Italic", systemImage: "italic")
            }
        }
        if block.type.supportsTextColor {
            Menu { InlineColorButtons() } label: {
                Label("Text Color", systemImage: "textformat")
            }
        }
        if block.type.supportsBackground {
            Menu { BlockColorButtons(selection: $block.bgColor) } label: {
                Label("Background", systemImage: "highlighter")
            }
        }

        Divider()

        Button("Duplicate", systemImage: "plus.square.on.square") { onDuplicate() }
        Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
    }
}

extension View {
    /// Attaches the block actions as a right-click context menu on Mac. On iOS
    /// the formatting bar handles these, and a context menu would fight the
    /// long-press reorder gesture, so it's a no-op there.
    @ViewBuilder
    func blockContextMenu(_ block: Binding<ContentBlock>,
                          insertAbove: @escaping (ContentBlockType) -> Void,
                          insertBelow: @escaping (ContentBlockType) -> Void,
                          duplicate: @escaping () -> Void,
                          delete: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.contextMenu {
            BlockMenuItems(block: block, onInsertAbove: insertAbove, onInsertBelow: insertBelow,
                           onDuplicate: duplicate, onDelete: delete)
        }
        #else
        self
        #endif
    }
}

// MARK: - Formatting bar (iOS keyboard accessory)

/// The floating formatting bar shown above the keyboard for the focused block.
/// Lives inside a `ToolbarItemGroup(placement: .keyboard)`.
struct BlockFormatBar: View {
    @Binding var block: ContentBlock
    let onInsertBelow: (ContentBlockType) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    var onDismissKeyboard: () -> Void = {}

    private func setType(_ t: ContentBlockType) {
        block.type = t
        if t == .todo, block.checked == nil { block.checked = false }
    }

    var body: some View {
        if block.type.supportsTextStyle {
            Button { RichTextActive.shared.apply(.bold) } label: {
                Image(systemName: "bold")
            }
            Button { RichTextActive.shared.apply(.italic) } label: {
                Image(systemName: "italic")
            }
        }
        if block.type.supportsTextColor {
            Menu { InlineColorButtons() } label: {
                Image(systemName: "textformat")
            }
        }
        if block.type.supportsBackground {
            Menu { BlockColorButtons(selection: $block.bgColor) } label: {
                Image(systemName: "highlighter")
            }
        }
        Menu {
            ForEach(ContentBlockType.allCases) { t in
                Button(t.label, systemImage: t.icon) { onInsertBelow(t) }
            }
        } label: { Image(systemName: "plus.square") }
        Menu {
            Menu {
                ForEach(ContentBlockType.allCases) { t in
                    Button(t.label, systemImage: t.icon) { setType(t) }
                }
            } label: { Label("Turn Into", systemImage: "arrow.triangle.2.circlepath") }
            Button("Duplicate", systemImage: "plus.square.on.square") { onDuplicate() }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        } label: { Image(systemName: "ellipsis.circle") }

        Spacer()
        Button("Done") { onDismissKeyboard() }
    }
}
