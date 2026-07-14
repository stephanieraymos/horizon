import SwiftUI

/// Egress-safe image view for private Storage objects. Caches the decoded bytes
/// keyed by STORAGE PATH (stable), so re-renders never re-download even though
/// the signed URL rotates. One fetch per path per app session; zero per-scroll
/// re-fetches (the failure mode that ran up egress in the sibling app).
struct CachedStorageImage<Placeholder: View>: View {
    let path: String?
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(path: String?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.path = path
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable() }
            else { placeholder() }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path else { image = nil; return }
        // Memory → disk → network, keyed by the stable storage path so a private
        // object is fetched once across app launches (not once per launch).
        let ui = await HorizonImageLoader.cachedStorageImage(path: path)
        if !Task.isCancelled { image = ui }
    }
}
