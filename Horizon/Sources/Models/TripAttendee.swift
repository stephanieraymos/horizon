import SwiftUI

/// RSVP status for a plan's guest.
enum RSVPStatus: String, Codable, CaseIterable, Hashable {
    case invited, going, maybe, declined

    var label: String {
        switch self {
        case .invited:  return "Invited"
        case .going:    return "Going"
        case .maybe:    return "Maybe"
        case .declined: return "Declined"
        }
    }
    var systemImage: String {
        switch self {
        case .invited:  return "envelope"
        case .going:    return "checkmark.circle.fill"
        case .maybe:    return "questionmark.circle"
        case .declined: return "xmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .invited:  return .secondary
        case .going:    return .green
        case .maybe:    return .orange
        case .declined: return .red
        }
    }
}

/// A row in `fam_trip_attendees` — event-specific status for a person on a plan.
/// People live in `people`/`fam_family_members` (memberID); ad-hoc non-family
/// guests carry just a `name`.
struct TripAttendee: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var familyID: UUID
    var memberID: UUID?
    var name: String?
    var status: RSVPStatus
    var plusOnes: Int

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case tripID = "trip_id"
        case familyID = "family_id"
        case memberID = "member_id"
        case plusOnes = "plus_ones"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self, forKey: .id)
        tripID   = try c.decode(UUID.self, forKey: .tripID)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        memberID = try c.decodeIfPresent(UUID.self, forKey: .memberID)
        name     = try c.decodeIfPresent(String.self, forKey: .name)
        status   = (try? c.decode(RSVPStatus.self, forKey: .status)) ?? .invited
        plusOnes = (try? c.decode(Int.self, forKey: .plusOnes)) ?? 0
    }

    init(id: UUID, tripID: UUID, familyID: UUID, memberID: UUID?, name: String?,
         status: RSVPStatus = .invited, plusOnes: Int = 0) {
        self.id = id; self.tripID = tripID; self.familyID = familyID
        self.memberID = memberID; self.name = name; self.status = status; self.plusOnes = plusOnes
    }
}
