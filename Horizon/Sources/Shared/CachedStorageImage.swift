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
        guard let path, let key = NSURL(string: "trip-docs:///\(path)") else { image = nil; return }
        if let cached = HorizonImageLoader.memory.object(forKey: key) { image = cached; return }
        do {
            let url = try await StorageService.signedURL(path: path)
            let (data, _) = try await HorizonImageLoader.session.data(from: url)
            guard !Task.isCancelled, let ui = UIImage(data: data) else { return }
            HorizonImageLoader.memory.setObject(ui, forKey: key)
            image = ui
        } catch {
            // Keep placeholder; transient failures shouldn't disrupt the list.
        }
    }
}
