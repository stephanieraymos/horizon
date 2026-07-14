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

    /// Loads a cover image (http URL or private Storage path) as a UIImage via
    /// the same caches the cached-image views use. For focal-point framing where
    /// the raw pixels are needed.
    static func loadCover(_ cover: String) async -> UIImage? {
        if cover.hasPrefix("http") {
            guard let url = URL(string: cover) else { return nil }
            if let c = memory.object(forKey: url as NSURL) { return c }
            guard let (data, _) = try? await session.data(from: url), let ui = UIImage(data: data) else { return nil }
            memory.setObject(ui, forKey: url as NSURL)
            return ui
        } else {
            return await cachedStorageImage(path: cover)
        }
    }

    // MARK: Private-object disk cache (keyed by stable storage path)

    private static let diskDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("horizon-img", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func diskURL(forPath path: String) -> URL {
        diskDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    /// Memory → disk → network fetch for a private Storage object, keyed by its
    /// stable PATH (signed URLs rotate, so we never key on the URL). Result: one
    /// network fetch per object across app launches, not once per launch — the
    /// egress win. iOS purges the Caches dir under storage pressure.
    static func cachedStorageImage(path: String) async -> UIImage? {
        guard let key = NSURL(string: "trip-docs:///\(path)") else { return nil }
        if let mem = memory.object(forKey: key) { return mem }
        let file = diskURL(forPath: path)
        if let data = try? Data(contentsOf: file), let ui = UIImage(data: data) {
            memory.setObject(ui, forKey: key)
            return ui
        }
        do {
            let url = try await StorageService.signedURL(path: path)
            let (data, _) = try await session.data(from: url)
            guard let ui = UIImage(data: data) else { return nil }
            memory.setObject(ui, forKey: key)
            try? data.write(to: file, options: .atomic)
            return ui
        } catch { return nil }
    }
}

/// Cover image rendered aspect-fill, positioned to a focal point (0..1) so the
/// banner can be re-framed without re-cropping the source.
struct AdjustableCoverImage<Placeholder: View>: View {
    let cover: String?
    var focus: UnitPoint = .center
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                let l = Self.layout(imageSize: image.size, frame: geo.size, focus: focus)
                Image(uiImage: image).resizable()
                    .frame(width: l.size.width, height: l.size.height)
                    .offset(x: l.offset.x, y: l.offset.y)
            } else {
                placeholder()
            }
        }
        .clipped()
        .task(id: cover) {
            image = nil
            if let c = cover?.nilIfBlank { image = await HorizonImageLoader.loadCover(c) }
        }
    }

    /// Aspect-fill size + offset that places `focus` at the frame's center.
    static func layout(imageSize: CGSize, frame: CGSize, focus: UnitPoint)
        -> (size: CGSize, offset: CGPoint) {
        guard imageSize.width > 0, imageSize.height > 0, frame.width > 0, frame.height > 0 else {
            return (frame, .zero)
        }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let overflow = CGSize(width: scaled.width - frame.width, height: scaled.height - frame.height)
        // focus 0 → show the leading/top edge; 0.5 → centered; 1 → trailing/bottom.
        let offX = (0.5 - focus.x) * overflow.width
        let offY = (0.5 - focus.y) * overflow.height
        return (scaled, CGPoint(x: offX, y: offY))
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
