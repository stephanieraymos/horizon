import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Inline editor for a single rich-document block (Notion-style). Reused by
/// Problems and Notes; image upload/fetch is injected so it stays store-agnostic.
struct ContentBlockRow: View {
    @Binding var block: ContentBlock
    @FocusState.Binding var focused: UUID?
    /// Drives programmatic focus for rich-text blocks (decoupled from FocusState).
    @Binding var focusRequest: UUID?
    /// (data, fileName, contentType) -> storage path
    let upload: (Data, String, String?) async throws -> String?
    /// Insert a new block right after the one with the given id, then focus it.
    var onInsertAfter: (UUID, ContentBlock) -> Void = { _, _ in }
    /// 1-based position for a numbered-list item (computed by the host editor).
    var ordinal: Int? = nil
    @Environment(\.openURL) private var openURL
    @State private var slashQuery: String?

    /// Custom text color for this block, or nil to use the default foreground.
    private var textColor: Color? { block.color.flatMap { Color(hex: $0) } }

    /// The accent (stripe / tint) for callout-style blocks. A custom background
    /// or text color fully overrides the block's signature color.
    private var accentColor: Color {
        block.bgColor.flatMap { Color(hex: $0) }
            ?? block.color.flatMap { Color(hex: $0) }
            ?? defaultAccent
    }
    private var defaultAccent: Color {
        block.type == .timeline ? Theme.Colors.brandAmber : Theme.Colors.brand
    }

    /// Plain blocks get a wrapping highlight; callout blocks fold the color into
    /// their own accent instead.
    private var isPlainBlock: Bool {
        switch block.type {
        case .text, .heading, .todo, .bullet, .numbered: true
        default: false
        }
    }

    var body: some View {
        emphasized(content)
            .modifier(BlockHighlight(hex: isPlainBlock ? block.bgColor : nil))
    }

    /// Applies whole-block bold/italic only when explicitly set, so a heading's
    /// default weight isn't disturbed.
    @ViewBuilder private func emphasized(_ v: some View) -> some View {
        switch (block.bold == true, block.italic == true) {
        case (true, true):   v.bold().italic()
        case (true, false):  v.bold()
        case (false, true):  v.italic()
        case (false, false): v
        }
    }

    /// Two-way bridge between the editor's run array and the block's stored
    /// runs (+ plain `text` mirror for search/preview).
    private var runsBinding: Binding<[RichRun]> {
        Binding(
            get: {
                if let r = block.runs, !r.isEmpty { return r }
                let t = block.text ?? ""
                return t.isEmpty ? [] : [RichRun(text: t)]
            },
            set: { newRuns in
                block.runs = newRuns.isEmpty ? nil : newRuns
                let plain = newRuns.plainText
                block.text = plain.isEmpty ? nil : plain
            }
        )
    }

    private func richConfig(size: CGFloat, weight: Font.Weight = .regular,
                            monospaced: Bool = false) -> RichTextConfig {
        RichTextConfig(fontSize: size, weight: weight, monospaced: monospaced,
                       baseColorHex: block.color)
    }

    private func richEditor(_ placeholder: String, _ config: RichTextConfig) -> some View {
        RichTextEditor(
            runs: runsBinding, placeholder: placeholder, config: config,
            blockID: block.id, focusRequest: $focusRequest,
            onPlainChange: { plain in smart(plain) }
        )
    }

    @ViewBuilder private var content: some View {
        switch block.type {
        case .heading:
            VStack(alignment: .leading, spacing: 4) {
                richEditor("Heading", richConfig(size: 22, weight: .bold))
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                slashMenu
            }

        case .text:
            VStack(alignment: .leading, spacing: 4) {
                richEditor("Write, or type “/” for blocks…", richConfig(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                slashMenu
            }

        case .code:
            VStack(alignment: .leading, spacing: 4) {
                richEditor("Code", richConfig(size: 15, monospaced: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9).padding(.horizontal, 11)
                    .background(block.bgColor != nil ? AnyShapeStyle(accentColor.opacity(0.14))
                                                     : AnyShapeStyle(Color.systemFill6),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Colors.hairline, lineWidth: 1))
                slashMenu
            }

        case .todo:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            block.checked = !(block.checked ?? false)
                        }
                    } label: {
                        Image(systemName: (block.checked ?? false) ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle((block.checked ?? false) ? Color.green : .secondary)
                    }
                    .buttonStyle(.plain)
                    richEditor("To-do", richConfig(size: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                slashMenu
            }

        case .bullet:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    Text("•").font(.body).foregroundStyle(textColor ?? .secondary)
                        .padding(.leading, 2)
                    richEditor("List item", richConfig(size: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                slashMenu
            }

        case .numbered:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(ordinal ?? 1).").font(.body).foregroundStyle(textColor ?? .secondary)
                        .monospacedDigit()
                    richEditor("List item", richConfig(size: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                slashMenu
            }

        case .keyFact:
            // Notion-style page property: a muted label column and a clean SF Pro
            // value in a soft, subtle card (no monospace, no heavy chrome).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Label", text: $block.label.orEmpty())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 118, alignment: .leading)
                TextField("Value", text: $block.value.orEmpty())
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let v = block.value, !v.isEmpty {
                    Button { copy(v) } label: {
                        Image(systemName: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.systemFill6,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .contact:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $block.label.orEmpty()).font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("Role / org", text: $block.role.orEmpty())
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: "phone").font(.caption2).foregroundStyle(.secondary)
                    TextField("Phone", text: $block.phone.orEmpty())
                        .font(.callout)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    if let p = block.phone, !p.isEmpty {
                        Button { tel(p) } label: { Image(systemName: "phone.fill") }
                            .buttonStyle(.plain).foregroundStyle(.green)
                        Button { copy(p) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).foregroundStyle(Theme.Colors.brand)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "envelope").font(.caption2).foregroundStyle(.secondary)
                    TextField("Email", text: $block.email.orEmpty())
                        .font(.callout)
                        #if os(iOS)
                        .keyboardType(.emailAddress).autocapitalization(.none)
                        #endif
                    if let e = block.email, !e.isEmpty {
                        Button { mail(e) } label: { Image(systemName: "paperplane.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.Colors.brand)
                    }
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(accentColor.opacity(0.6)).frame(width: 3)
            }

        case .timeline:
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.caption2).foregroundStyle(accentColor)
                    TextField("Date", text: $block.date.orEmpty())
                        .font(.caption.weight(.semibold)).foregroundStyle(accentColor)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                TextField("Title", text: $block.label.orEmpty())
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("What happened…", text: $block.textValue, axis: .vertical)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(accentColor.opacity(0.7)).frame(width: 3)
            }

        case .image:
            ImageBlockView(block: $block, upload: upload)

        case .link:
            HStack(spacing: 10) {
                Image(systemName: "link").font(.callout).foregroundStyle(Theme.Colors.brand)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Link text", text: $block.label.orEmpty())
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("https://…", text: $block.value.orEmpty())
                        .font(.caption).foregroundStyle(.secondary)
                        .noAutoCapitalize()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let url = linkURL(block.value) {
                    Button { openURL(url) } label: {
                        Image(systemName: "arrow.up.right.square.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.Colors.brand)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.brand.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .divider:
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Slash menu + markdown

    @ViewBuilder private var slashMenu: some View {
        if let q = slashQuery {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(slashMatches(q)) { type in
                    Button { convert(to: type) } label: {
                        Label(type.label, systemImage: type.icon)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: 1))
        }
    }

    private func slashMatches(_ q: String) -> [ContentBlockType] {
        let all = ContentBlockType.allCases
        guard !q.isEmpty else { return all }
        return all.filter { $0.label.lowercased().contains(q) || $0.rawValue.contains(q) }
    }

    private func convert(to type: ContentBlockType) {
        block.type = type
        block.text = nil
        block.runs = nil
        if type == .todo { block.checked = false }
        slashQuery = nil
        if type == .divider { onInsertAfter(block.id, ContentBlock(type: .text)) }
    }

    /// Slash commands, markdown shortcuts, and Enter-to-new-block.
    private func smart(_ new: String) {
        // "/" opens the block menu (filtered by what follows).
        if new.hasPrefix("/") { slashQuery = String(new.dropFirst()).lowercased(); return }
        if slashQuery != nil { slashQuery = nil }

        // Enter splits the block: text before stays, text after becomes a new
        // block. Lists/to-dos continue the same type; an empty item + Enter ends
        // the list (converts the empty item to plain text).
        if let nl = new.firstIndex(of: "\n") {
            let head = String(new[..<nl])
            let tail = String(new[new.index(after: nl)...])
            let isListy = block.type == .bullet || block.type == .numbered || block.type == .todo
            if isListy && head.isEmpty && tail.isEmpty {
                block.type = .text          // exit the list
                block.runs = nil
                return
            }
            block.text = head.isEmpty ? nil : head
            block.runs = nil
            var nb = ContentBlock(type: isListy ? block.type : .text)
            if nb.type == .todo { nb.checked = false }
            nb.text = tail.isEmpty ? nil : tail
            onInsertAfter(block.id, nb)
            return
        }

        // Markdown prefixes (only from a plain text block).
        guard block.type == .text else { return }
        func set(_ t: ContentBlockType, strip: Int) {
            block.type = t
            if t == .todo { block.checked = false }
            block.text = String(new.dropFirst(strip))
            block.runs = nil
        }
        if new.hasPrefix("### ")        { set(.heading, strip: 4) }
        else if new.hasPrefix("## ")     { set(.heading, strip: 3) }
        else if new.hasPrefix("# ")      { set(.heading, strip: 2) }
        else if new.hasPrefix("- [ ] ")  { set(.todo, strip: 6) }
        else if new.hasPrefix("[ ] ")    { set(.todo, strip: 4) }
        else if new.hasPrefix("[] ")     { set(.todo, strip: 3) }
        else if new.hasPrefix("- ")      { set(.bullet, strip: 2) }
        else if new.hasPrefix("* ")      { set(.bullet, strip: 2) }
        else if new.hasPrefix("```")     { set(.code, strip: 3) }
        else if let n = numberedPrefix(new) { set(.numbered, strip: n) }
        else if new == "---" || new == "--- " {
            block.type = .divider; block.text = nil; block.runs = nil
            onInsertAfter(block.id, ContentBlock(type: .text))
        }
    }

    /// Length of a leading "N. " numbered-list marker, or nil if absent.
    private func numberedPrefix(_ s: String) -> Int? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let digits = s[s.startIndex..<dot]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        let after = s.index(after: dot)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return s.distance(from: s.startIndex, to: after) + 1
    }

    // MARK: - Actions

    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
    private func tel(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { openURL(url) }
    }
    private func mail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") { openURL(url) }
    }

    /// Normalize a typed string into an openable URL (default to https://).
    private func linkURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("://") { return URL(string: raw) }
        return URL(string: "https://\(raw)")
    }
}

/// Wraps a plain block in a soft background highlight when a background color
/// is set; otherwise passes the content through untouched.
struct BlockHighlight: ViewModifier {
    let hex: String?
    func body(content: Content) -> some View {
        if let c = hex.flatMap({ Color(hex: $0) }) {
            content
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(c.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
        }
    }
}

extension Binding where Value == String? {
    /// Bridges an optional String column to a TextField (empty ⇒ nil).
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

/// An image block: pick/upload a photo or file, show it, add a caption.
private struct ImageBlockView: View {
    @Binding var block: ContentBlock
    let upload: (Data, String, String?) async throws -> String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var uploading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = block.filePath {
                // Egress-safe: path-keyed cache (memory → disk → network once).
                CachedStorageImage(path: path) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.systemFill6)
                        .frame(height: 160).overlay { ProgressView() }
                }
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                TextField("Caption (optional)", text: $block.textValue)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                    Button { showFileImporter = true } label: {
                        Label("File", systemImage: "doc")
                    }
                    if uploading { ProgressView().padding(.leading, 4) }
                }
                .font(.subheadline)
                if let errorText {
                    Text(errorText)
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                errorText = nil
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await store(data, name: "photo-\(Int(Date().timeIntervalSince1970)).jpg",
                                     type: "image/jpeg")
                    } else {
                        errorText = "Couldn't read that photo. Try a different one."
                    }
                } catch {
                    errorText = "Couldn't load photo: \(error.localizedDescription)"
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .pdf, .item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                Task {
                    let access = u.startAccessingSecurityScopedResource()
                    defer { if access { u.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: u) {
                        await store(data, name: u.lastPathComponent,
                                     type: UTType(filenameExtension: u.pathExtension)?.preferredMIMEType)
                    }
                }
            }
        }
    }

    private func store(_ data: Data, name: String, type: String?) async {
        uploading = true
        defer { uploading = false }
        do {
            if let path = try await upload(data, name, type) {
                block.filePath = path
                block.fileName = name
                errorText = nil
            } else {
                errorText = "Upload failed. Check your connection and try again."
            }
        } catch {
            errorText = "Upload failed: \(error.localizedDescription)"
        }
    }
}
