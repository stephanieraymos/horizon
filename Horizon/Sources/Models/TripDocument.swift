import Foundation

enum DocumentKind: String, CaseIterable, Hashable {
    case confirmation = "confirmation"
    case ticket, passport, screenshot, pdf, link, other

    var label: String {
        switch self {
        case .confirmation: "Confirmation"; case .ticket: "Ticket"; case .passport: "Passport"
        case .screenshot: "Screenshot"; case .pdf: "PDF"; case .link: "Link"; case .other: "Document"
        }
    }
    var systemImage: String {
        switch self {
        case .confirmation: "checkmark.seal"; case .ticket: "ticket"; case .passport: "person.text.rectangle"
        case .screenshot: "photo"; case .pdf: "doc.richtext"; case .link: "link"; case .other: "doc"
        }
    }
}

/// A clean display string for a URL when no title is given — host without the
/// scheme or "www.", e.g. "https://www.amazon.com/dp/B0..." → "amazon.com".
func prettyURLText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard let comps = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
          var host = comps.host else { return trimmed }
    if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
    // Include a short first path segment when it adds meaning (e.g. github.com/user).
    let firstSegment = comps.path.split(separator: "/").first.map(String.init)
    if let seg = firstSegment, seg.count <= 20, host.split(separator: ".").count <= 2 {
        return "\(host)/\(seg)"
    }
    return host
}

/// Mirror of `fam_trip_documents`. Files live in the private `trip-docs` bucket
/// under `<family_id>/<trip_id>/<uuid>.<ext>`.
struct TripDocument: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var tripID: UUID?
    var reservationID: UUID?
    var kind: String
    var storagePath: String?
    var fileName: String?
    var contentType: String?
    var title: String?
    var notes: String?
    var url: String?
    var isSensitive: Bool
    var createdBy: UUID?
    var createdAt: Date?

    var isImage: Bool { (contentType ?? "").hasPrefix("image") }
    var isLink: Bool { kind == DocumentKind.link.rawValue || (storagePath == nil && url != nil) }
    var linkURL: URL? {
        guard let u = url?.nilIfBlank else { return nil }
        return URL(string: u.contains("://") ? u : "https://\(u)")
    }
    /// Best label: explicit title, else a prettified URL, else the file name.
    var displayName: String {
        if let t = title?.nilIfBlank { return t }
        if let u = url?.nilIfBlank { return prettyURLText(u) }
        return fileName ?? "Resource"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case tripID = "trip_id"
        case reservationID = "reservation_id"
        case kind
        case storagePath = "storage_path"
        case fileName = "file_name"
        case contentType = "content_type"
        case title, notes, url
        case isSensitive = "is_sensitive"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), familyID: UUID, tripID: UUID?, reservationID: UUID? = nil,
         kind: DocumentKind, storagePath: String? = nil, url: String? = nil,
         fileName: String? = nil, contentType: String? = nil, title: String? = nil,
         isSensitive: Bool = false, createdBy: UUID? = nil) {
        self.id = id; self.familyID = familyID; self.tripID = tripID; self.reservationID = reservationID
        self.kind = kind.rawValue
        self.storagePath = storagePath; self.url = url; self.fileName = fileName; self.contentType = contentType
        self.title = title; self.isSensitive = isSensitive; self.createdBy = createdBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID)
        reservationID = try c.decodeIfPresent(UUID.self, forKey: .reservationID)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        storagePath = try c.decodeIfPresent(String.self, forKey: .storagePath)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        isSensitive = try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encodeIfPresent(tripID, forKey: .tripID)
        try c.encodeIfPresent(reservationID, forKey: .reservationID)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(storagePath, forKey: .storagePath)
        try c.encodeIfPresent(fileName, forKey: .fileName)
        try c.encodeIfPresent(contentType, forKey: .contentType)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encode(isSensitive, forKey: .isSensitive)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
    }
}
