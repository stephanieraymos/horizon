import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TripDocumentsSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var viewing: TripDocument?
    @State private var uploading = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Documents").font(.title3.bold())
                if uploading { ProgressView().controlSize(.small) }
                Spacer()
                Menu {
                    PhotosPicker("Photo / screenshot", selection: $photoItem, matching: .images)
                    Button("File (PDF…)", systemImage: "doc") { showFileImporter = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .tint(Theme.Colors.brand)
            }

            if store.documents.isEmpty {
                Text("Add booking confirmations, tickets, or passports.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.documents) { doc in
                        DocumentThumb(doc: doc)
                            .onTapGesture { if doc.isImage { viewing = doc } }
                            .contextMenu {
                                Button("Delete", role: .destructive) { Task { await store.deleteDocument(doc) } }
                            }
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in Task { await handlePhoto(item) } }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .image, .plainText, .item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await handleFile(url) } }
        }
        .sheet(item: $viewing) { DocumentViewer(doc: $0) }
    }

    private func handlePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploading = true; defer { uploading = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let name = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        await store.addDocument(familyID: familyID, data: data, fileName: name,
                                contentType: "image/jpeg", kind: .screenshot,
                                createdBy: family.currentMember?.id)
    }

    private func handleFile(_ url: URL) async {
        uploading = true; defer { uploading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let type = UTType(filenameExtension: url.pathExtension)
        let contentType = type?.preferredMIMEType ?? "application/octet-stream"
        let kind: DocumentKind = (type?.conforms(to: .pdf) ?? false) ? .pdf : .other
        await store.addDocument(familyID: familyID, data: data, fileName: url.lastPathComponent,
                                contentType: contentType, kind: kind, createdBy: family.currentMember?.id)
    }
}

private struct DocumentThumb: View {
    let doc: TripDocument

    var body: some View {
        VStack(spacing: 4) {
            if doc.isImage {
                CachedStorageImage(path: doc.storagePath) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.systemFill6)
                        .overlay { ProgressView() }
                }
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.systemFill6)
                    .frame(width: 92, height: 92)
                    .overlay {
                        Image(systemName: DocumentKind(rawValue: doc.kind)?.systemImage ?? "doc")
                            .font(.title).foregroundStyle(Theme.Colors.brand)
                    }
            }
            Text(doc.title ?? doc.fileName ?? "File")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 92)
        }
    }
}

private struct DocumentViewer: View {
    let doc: TripDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CachedStorageImage(path: doc.storagePath) {
                ProgressView()
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(doc.title ?? "Document")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
