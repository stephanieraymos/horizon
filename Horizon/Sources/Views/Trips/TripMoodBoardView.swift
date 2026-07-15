import SwiftUI
import PhotosUI

/// A trip's mood board: a photo collage backed by the trip's album. Photos are
/// taggable on upload and attributed to the uploader; the board filters by both.
struct TripMoodBoardView: View {
    let tripID: UUID
    let familyID: UUID
    let tripName: String

    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var store = MoodBoardStore()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingJPEGs: [Data] = []
    @State private var showUploadSheet = false
    @State private var isPreparing = false

    // Filters
    @State private var selectedUploader: UUID?
    @State private var selectedTag: String?

    // Full-screen viewer
    @State private var viewing: MoodPhoto?

    private let columns = [GridItem(.flexible(), spacing: 3),
                           GridItem(.flexible(), spacing: 3),
                           GridItem(.flexible(), spacing: 3)]

    private var filtered: [MoodPhoto] {
        store.photos.filter { p in
            (selectedUploader == nil || p.addedBy == selectedUploader) &&
            (selectedTag == nil || (p.tag?.caseInsensitiveCompare(selectedTag!) == .orderedSame))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.photos.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.photos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Add photos to build this trip's mood board. Tag them and they'll be filterable."))
                } else {
                    ScrollView {
                        if !store.uploaderIDs.isEmpty || !store.tags.isEmpty {
                            filterBar.padding(.horizontal).padding(.top, 8)
                        }
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(filtered) { photo in
                                tile(photo)
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.top, 6)
                    }
                }
            }
            .navigationTitle("Mood Board")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerItems, matching: .images) {
                        if isPreparing || store.isUploading { ProgressView() }
                        else { Image(systemName: "plus") }
                    }
                    .disabled(isPreparing || store.isUploading)
                }
            }
            .task {
                await store.load(tripID: tripID, familyID: familyID, tripName: tripName,
                                 createdBy: family.currentMember?.userID)
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await prepare(items) }
            }
            .sheet(isPresented: $showUploadSheet) {
                MoodUploadSheet(count: pendingJPEGs.count, existingTags: store.tags) { tag, caption in
                    Task {
                        await store.addPhotos(pendingJPEGs, tag: tag, caption: caption,
                                              familyID: familyID, addedBy: family.currentMember?.userID)
                        pendingJPEGs = []
                    }
                } onCancel: {
                    pendingJPEGs = []
                }
            }
            .fullScreenCover(item: $viewing) { photo in
                MoodPhotoViewer(photo: photo,
                                uploaderName: uploaderName(photo.addedBy)) {
                    Task { await store.delete(photo); viewing = nil }
                } onClose: { viewing = nil }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }

    // MARK: - Tiles & filters

    private func tile(_ photo: MoodPhoto) -> some View {
        Button { viewing = photo } label: {
            CachedRemoteImage(url: URL(string: photo.url)) {
                Rectangle().fill(Color(.tertiarySystemFill))
                    .overlay(ProgressView())
            }
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let tag = photo.tag?.nilIfBlank {
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                PersonAvatar(name: uploaderName(photo.addedBy),
                             avatarURL: uploaderAvatar(photo.addedBy), size: 20)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.uploaderIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MoodChip(label: "Everyone", isActive: selectedUploader == nil) {
                            selectedUploader = nil
                        }
                        ForEach(store.uploaderIDs, id: \.self) { uid in
                            MoodChip(label: uploaderName(uid), isActive: selectedUploader == uid) {
                                selectedUploader = (selectedUploader == uid) ? nil : uid
                            }
                        }
                    }
                }
            }
            if !store.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    MoodChip(label: "All tags", isActive: selectedTag == nil) { selectedTag = nil }
                    ForEach(store.tags, id: \.self) { tag in
                        MoodChip(label: tag, isActive: selectedTag?.caseInsensitiveCompare(tag) == .orderedSame) {
                            selectedTag = (selectedTag?.caseInsensitiveCompare(tag) == .orderedSame) ? nil : tag
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func uploaderName(_ id: UUID?) -> String {
        guard let id else { return "Someone" }
        return family.members.first { $0.userID == id }?.name ?? "Someone"
    }
    private func uploaderAvatar(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return family.members.first { $0.userID == id }?.avatarURL
    }

    /// Load picked items and re-encode to JPEG, then present the tag sheet.
    private func prepare(_ items: [PhotosPickerItem]) async {
        isPreparing = true
        defer { isPreparing = false; pickerItems = [] }
        var out: [Data] = []
        for item in items {
            if let jpeg = await item.loadUploadJPEG() { out.append(jpeg) }
        }
        guard !out.isEmpty else { return }
        pendingJPEGs = out
        showUploadSheet = true
    }
}

// MARK: - Chip

private struct MoodChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isActive ? Theme.Colors.brand.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isActive ? Theme.Colors.brand : .secondary)
                .overlay(Capsule().stroke(isActive ? Theme.Colors.brand.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Upload sheet (tag + caption)

private struct MoodUploadSheet: View {
    let count: Int
    let existingTags: [String]
    let onAdd: (_ tag: String?, _ caption: String?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tag = ""
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ComboField(
                        placeholder: "Tag (e.g. food, views, hotel)",
                        text: $tag,
                        options: existingTags.map { .init(id: $0, name: $0, icon: "tag") },
                        pickIcon: "tag",
                        onPick: { tag = $0.name },
                        onAdd: { tag = $0 })
                } header: {
                    Text("Tag")
                } footer: {
                    Text("Tags let you filter the mood board (all \(count) photo\(count == 1 ? "" : "s") get this tag).")
                }
                Section("Caption (optional)") {
                    TextField("Add a caption", text: $caption, axis: .vertical).lineLimit(1...3)
                }
            }
            .navigationTitle("Add \(count) Photo\(count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(tag.nilIfBlank, caption.nilIfBlank)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Full-screen viewer

private struct MoodPhotoViewer: View {
    let photo: MoodPhoto
    let uploaderName: String
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                CachedRemoteImage(url: URL(string: photo.url)) { ProgressView().tint(.white) }
                    .scaledToFit()
            }
            .overlay(alignment: .bottom) {
                if let caption = photo.caption?.nilIfBlank {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            }
            .navigationTitle(uploaderName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { onClose() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}
