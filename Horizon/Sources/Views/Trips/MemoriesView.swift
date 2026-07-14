import SwiftUI

/// A photo grid of a trip's image documents — the post-trip recap.
struct MemoriesView: View {
    let store: TripDetailStore
    let tripName: String
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]
    private var images: [TripDocument] { store.documents.filter(\.isImage) }

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle.angled",
                        description: Text("Add photos in the trip's Documents section and they'll appear here."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(images) { doc in
                                CachedStorageImage(path: doc.storagePath) {
                                    Rectangle().fill(Color.systemFill6).overlay { ProgressView() }
                                }
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .navigationTitle(tripName)
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
