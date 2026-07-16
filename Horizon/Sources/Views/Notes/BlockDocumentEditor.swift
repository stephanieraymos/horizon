import SwiftUI

/// Reusable Notion-style block-document editor lifted from Orbit, decoupled from
/// any store. Edits a `[ContentBlock]` binding: text, headings, to-dos, bullets,
/// numbered lists, code, dividers — with inline bold/italic/color and rich-text
/// paste. Image blocks are stubbed here (enabled once a storage bucket lands).
struct BlockDocumentEditor: View {
    @Binding var blocks: [ContentBlock]
    @FocusState private var focused: UUID?
    @State private var focusRequest: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach($blocks) { $block in
                    let blockId = block.id
                    ContentBlockRow(
                        block: $block, focused: $focused, focusRequest: $focusRequest,
                        upload: { _, _, _ in nil },
                        onInsertAfter: { afterId, nb in insertAfter(afterId, nb, proxy: proxy) },
                        ordinal: numberedOrdinals[block.id]
                    )
                    .blockContextMenu($block,
                        insertAbove: { t in insertRelative(blockId, t, above: true, proxy: proxy) },
                        insertBelow: { t in insertRelative(blockId, t, above: false, proxy: proxy) },
                        duplicate: { duplicate(blockId) },
                        delete: { deleteBlock(blockId) })
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                    .id(blockId)
                }
                .onDelete { blocks.remove(atOffsets: $0) }
                .onMove { blocks.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                if let b = focusedBlockBinding {
                    BlockFormatBar(block: b,
                                   onInsertBelow: { t in insertRelative(b.wrappedValue.id, t, above: false, proxy: nil) },
                                   onDuplicate: { duplicate(b.wrappedValue.id) },
                                   onDelete: { deleteBlock(b.wrappedValue.id) },
                                   onDismissKeyboard: { focused = nil })
                } else {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            #endif
        }
        .onAppear {
            if blocks.isEmpty {
                let b = ContentBlock(type: .text)
                blocks = [b]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focusRequest = b.id }
            }
        }
    }

    /// Blocks worth persisting — drops empty text-style blocks.
    static func cleaned(_ list: [ContentBlock]) -> [ContentBlock] {
        list.filter { b in
            guard [.text, .heading, .todo, .bullet, .numbered, .code].contains(b.type) else { return true }
            return !(b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var numberedOrdinals: [UUID: Int] {
        var map: [UUID: Int] = [:]; var n = 0
        for b in blocks { if b.type == .numbered { n += 1; map[b.id] = n } else { n = 0 } }
        return map
    }

    private func makeBlock(_ type: ContentBlockType) -> ContentBlock {
        var block = ContentBlock(type: type)
        if type == .timeline {
            let f = DateFormatter(); f.dateFormat = "MMM d"; block.date = f.string(from: Date())
        }
        return block
    }

    private var focusedBlockBinding: Binding<ContentBlock>? {
        guard let id = focused, let i = blocks.firstIndex(where: { $0.id == id }) else { return nil }
        return $blocks[i]
    }

    private func focusNew(_ block: ContentBlock) {
        switch block.type {
        case .text, .heading, .todo, .bullet, .numbered, .code: focusRequest = block.id
        case .divider, .image: break
        default: focused = block.id
        }
    }

    private func insertAfter(_ afterId: UUID, _ nb: ContentBlock, proxy: ScrollViewProxy) {
        if let i = blocks.firstIndex(where: { $0.id == afterId }) { blocks.insert(nb, at: i + 1) }
        else { blocks.append(nb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation { proxy.scrollTo(nb.id, anchor: .center) }
            focusNew(nb)
        }
    }

    private func insertRelative(_ anchorId: UUID, _ type: ContentBlockType, above: Bool, proxy: ScrollViewProxy?) {
        let nb = makeBlock(type)
        if let i = blocks.firstIndex(where: { $0.id == anchorId }) { blocks.insert(nb, at: above ? i : i + 1) }
        else { blocks.append(nb) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation { proxy?.scrollTo(nb.id, anchor: .center) }
            focusNew(nb)
        }
    }

    private func duplicate(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks.insert(blocks[i].duplicated(), at: i + 1)
    }

    private func deleteBlock(_ id: UUID) { blocks.removeAll { $0.id == id } }
}
