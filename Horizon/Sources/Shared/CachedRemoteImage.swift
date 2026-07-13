import SwiftUI

/// Image loading for Horizon. EVERY remote image MUST go through this — never
/// use bare `AsyncImage`, which keeps no disk cache and re-downloads on each
/// appearance/scroll. That pattern is what blew through Supabase egress in the
/// sibling app.
///
/// Two cache layers: an in-memory `NSCache` (same URL rendered twice = zero
/// network) and the shared on-disk `URLCache` configured at app launch
/// (`returnCacheDataElseLoad`, so a previously fetched object never re-egresses).
///
/// IMPORTANT: pass a STABLE url. Supabase *signed* URLs carry a rotating token,
/// so a fresh signed URL every render defeats both caches. Prefer public-bucket
/// URLs, or cache the signed URL string per storage path and reuse it until it
/// is near expiry.
enum HorizonImageLoader {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache.shared
        return URLSession(configuration: config)
    }()

    // NSCache is internally thread-safe; the type just isn't marked Sendable.
    nonisolated(unsafe) static let memory: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 300
        return c
    }()

    /// Call once at app launch to give the shared disk cache real capacity
    /// (the default is far too small to hold photos across sessions).
    static func configureSharedCache() {
        URLCache.shared = URLCache(memoryCapacity: 50_000_000,   // 50 MB
                                   diskCapacity: 500_000_000,    // 500 MB
                                   directory: nil)
    }
}

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let cached = HorizonImageLoader.memory.object(forKey: url as NSURL) {
            image = cached; return
        }
        do {
            let (data, _) = try await HorizonImageLoader.session.data(from: url)
            guard !Task.isCancelled, let ui = UIImage(data: data) else { return }
            HorizonImageLoader.memory.setObject(ui, forKey: url as NSURL)
            image = ui
        } catch {
            // Leave placeholder showing; a transient failure shouldn't crash the row.
        }
    }
}

extension CachedRemoteImage where Placeholder == Color {
    /// Convenience with a plain neutral placeholder.
    init(url: URL?) {
        self.init(url: url) { Color.secondary.opacity(0.12) }
    }
}
