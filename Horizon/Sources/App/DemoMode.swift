#if DEBUG
import Foundation

/// Debug builds only: launch with `-HorizonDemo` to skip sign-in and fill the
/// stores with sample data, so screens past the auth gate can be screenshotted
/// on a simulator. A session can't sign in on her behalf, and until this existed
/// nothing in Horizon past sign-in had ever been seen rendering in a session.
///
/// The whole file is `#if DEBUG`, as are its call sites, so a TestFlight build
/// has no demo path at all. While active, `TripsStore`, `EventsStore` and
/// `FamilyStore` treat `load()` as a no-op — signed out, a load returns zero rows
/// and would wipe the sample data the moment any view refreshed.
enum DemoMode {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-HorizonDemo") }

    @MainActor
    static func seed(family: FamilyStore, trips: TripsStore, events: EventsStore) {
        let familyID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
        func born(nextBirthdayIn n: Int, turning age: Int) -> Date {
            cal.date(byAdding: .year, value: -age, to: day(n))!
        }

        let me = FamilyMember(familyID: familyID, userID: UUID(), name: "Stephanie", role: .admin,
                              birthday: born(nextBirthdayIn: 62, turning: 34))
        family.currentMember = me
        family.members = [
            me,
            FamilyMember(familyID: familyID, name: "Alex", role: .admin,
                         birthday: born(nextBirthdayIn: 4, turning: 35)),
            FamilyMember(familyID: familyID, name: "Oliver", role: .child,
                         birthday: born(nextBirthdayIn: 19, turning: 10)),
            FamilyMember(familyID: familyID, name: "Grandma Jo", role: .none,
                         birthday: born(nextBirthdayIn: 45, turning: 72), householdType: "extended"),
        ]

        let maui = Trip(familyID: familyID, name: "Maui", kind: .trip, destination: "Kaanapali, Maui",
                        departDate: day(12), returnDate: day(19),
                        travelers: ["Stephanie", "Alex", "Oliver"],
                        // A cover so the Change / Reframe pills render. It won't load
                        // signed out; the pills only need the URL to be set.
                        coverPhotoURL: "demo/maui.jpg", status: .booked)
        trips.trips = [
            maui,
            Trip(familyID: familyID, name: "Tahoe weekend", kind: .trip, destination: "South Lake Tahoe",
                 departDate: day(-1), returnDate: day(2), status: .inProgress),
            Trip(familyID: familyID, name: "Disneyland", kind: .trip, destination: "Anaheim",
                 departDate: day(38), returnDate: day(41), status: .planning),
            {
                // A festival she drives home from each night: 4 days, not 3 nights.
                var fest = Trip(familyID: familyID, name: "Aftershock", kind: .trip,
                                destination: "Discovery Park",
                                departDate: day(18), returnDate: day(21), status: .planning)
                fest.overnight = false
                return fest
            }(),
            Trip(familyID: familyID, name: "Oliver's 10th birthday party", kind: .party,
                 destination: "Backyard", departDate: day(9), travelers: ["Oliver"], status: .booked),
            Trip(familyID: familyID, name: "Omakase night", kind: .dinner,
                 destination: "Kusakabe", departDate: day(6), status: .booked),
            Trip(familyID: familyID, name: "Yosemite", kind: .trip, destination: "Yosemite Valley",
                 departDate: day(-40), returnDate: day(-37), status: .done),
            Trip(familyID: familyID, name: "Japan", kind: .trip, destination: "Tokyo"),
        ]

        events.replaceForDemo([
            FamilyEvent(id: UUID(), familyID: familyID, title: "Our anniversary",
                        eventType: FamilyEventType.anniversary.rawValue,
                        eventDate: cal.date(byAdding: .year, value: -12, to: day(27))!,
                        isAnnual: true, emoji: "💍"),
            FamilyEvent(id: UUID(), familyID: familyID, title: "Halloween",
                        eventType: FamilyEventType.holiday.rawValue,
                        eventDate: cal.date(from: DateComponents(year: 2000, month: 10, day: 31))!,
                        isAnnual: true, emoji: "🎃"),
            FamilyEvent(id: UUID(), familyID: familyID, title: "Half marathon",
                        eventType: FamilyEventType.milestone.rawValue, eventDate: day(53), emoji: "🏃‍♀️"),
            FamilyEvent(id: UUID(), familyID: familyID, title: "Last day of school",
                        eventType: FamilyEventType.other.rawValue, eventDate: day(160)),
            // The trip-linked row syncCountdown writes for Maui. It must NOT show a
            // second time — that duplicate is one of the bugs this screen fixes.
            FamilyEvent(id: UUID(), familyID: familyID, title: "Maui",
                        eventType: FamilyEventType.vacation.rawValue, eventDate: day(12),
                        emoji: "✈️", tripID: maui.id),
        ])
    }
}

extension FamilyMember {
    /// Demo data only — the real rows decode from `fam_family_members`.
    init(familyID: UUID, userID: UUID? = nil, name: String, role: FamilyRole,
         birthday: Date? = nil, householdType: String? = "household") {
        self.id = UUID()
        self.familyID = familyID
        self.userID = userID
        self.name = name
        self.role = role
        self.avatarURL = nil
        self.birthday = birthday
        self.householdType = householdType
        self.createdAt = Date()
    }
}
#endif
