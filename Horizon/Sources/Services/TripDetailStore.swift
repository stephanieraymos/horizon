import Foundation
import Observation
import Supabase

/// Per-trip sub-data: typed reservations + day-by-day itinerary. One instance
/// per open TripDetailView.
@Observable
@MainActor
final class TripDetailStore {
    let tripID: UUID
    var reservations: [Reservation] = []
    var itinerary: [ItineraryDay] = []
    var packing: [PackingItem] = []
    var expenses: [Expense] = []
    var splits: [ExpenseSplit] = []
    var documents: [TripDocument] = []
    var todos: [TripTodo] = []
    var tripPlaces: [TripPlace] = []
    var isLoading = false
    var errorMessage: String?

    init(tripID: UUID) { self.tripID = tripID }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let res = fetchReservations()
        async let days = fetchItinerary()
        async let pack = fetchPacking()
        async let exp = fetchExpenses()
        reservations = await res
        itinerary = await days
        packing = await pack
        expenses = await exp
        splits = await fetchSplits(for: expenses.map(\.id))
        documents = await fetchDocuments()
        todos = await fetchTodos()
        tripPlaces = await fetchTripPlaces()
    }

    // MARK: Trip places (multiple destinations)

    private func fetchTripPlaces() async -> [TripPlace] {
        do {
            return try await supabase.from("fam_trip_places")
                .select().eq("trip_id", value: tripID).order("sort").execute().value
        } catch { return [] }
    }

    /// Links a place to this trip (idempotent on the unique trip/place pair).
    func linkPlace(placeID: UUID, familyID: UUID) async {
        guard !tripPlaces.contains(where: { $0.placeID == placeID }) else { return }
        let row = TripPlace(tripID: tripID, placeID: placeID, familyID: familyID,
                            sort: (tripPlaces.map(\.sort).max() ?? -1) + 1)
        do {
            try await supabase.from("fam_trip_places").insert(row).execute()
            tripPlaces.append(row)
        } catch { errorMessage = error.localizedDescription }
    }

    func unlinkPlace(_ tripPlace: TripPlace) async {
        do {
            try await supabase.from("fam_trip_places").delete().eq("id", value: tripPlace.id).execute()
            tripPlaces.removeAll { $0.id == tripPlace.id }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: To-dos (pre-trip checklist)

    private func fetchTodos() async -> [TripTodo] {
        do {
            return try await supabase.from("fam_trip_todos")
                .select().eq("trip_id", value: tripID)
                .order("done").order("sort").order("created_at")
                .execute().value
        } catch { return [] }
    }

    func saveTodo(_ todo: TripTodo) async {
        do {
            try await supabase.from("fam_trip_todos").upsert(todo).execute()
            if let i = todos.firstIndex(where: { $0.id == todo.id }) { todos[i] = todo }
            else { todos.append(todo) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Optimistic done toggle.
    func toggleTodo(_ todo: TripTodo) async {
        var updated = todo
        updated.done.toggle()
        if let i = todos.firstIndex(where: { $0.id == todo.id }) { todos[i] = updated }
        do {
            try await supabase.from("fam_trip_todos")
                .update(["done": updated.done]).eq("id", value: todo.id).execute()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteTodo(_ todo: TripTodo) async {
        do {
            try await supabase.from("fam_trip_todos").delete().eq("id", value: todo.id).execute()
            todos.removeAll { $0.id == todo.id }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Shopping ↔ expenses (unified spending)

    /// Items still to buy (not yet purchased) — the shopping list view.
    var shoppingItems: [Expense] { expenses.filter { !$0.isPurchased } }
    /// Purchased items — the expense ledger view.
    var purchasedExpenses: [Expense] { expenses.filter(\.isPurchased) }

    var shoppingByTag: [(tag: String, items: [Expense])] {
        Dictionary(grouping: shoppingItems, by: { $0.tag?.nilIfBlank ?? "Other" })
            .map { (tag: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.tag < $1.tag }
    }
    var shoppingTags: [String] {
        Array(Set(expenses.compactMap { $0.tag?.nilIfBlank })).sorted()
    }
    /// Shopping items grouped by store (nil/blank store → "No store"), for the
    /// group-by-store view. Sorted case-insensitively, with "No store" last.
    var shoppingByStore: [(store: String, items: [Expense])] {
        Dictionary(grouping: shoppingItems, by: { $0.purchasedFrom?.nilIfBlank ?? "No store" })
            .map { (store: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted {
                if $0.store == "No store" { return false }
                if $1.store == "No store" { return true }
                return $0.store.localizedCaseInsensitiveCompare($1.store) == .orderedAscending
            }
    }
    /// Distinct stores among the to-buy items — powers the filter chips.
    var shoppingStoresInList: [String] {
        Array(Set(shoppingItems.compactMap { $0.purchasedFrom?.nilIfBlank }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    var shoppingToBuyCount: Int { shoppingItems.count }
    /// Estimated cost of everything still to buy (projected spend).
    var shoppingProjected: Double { shoppingItems.reduce(0) { $0 + $1.amount } }

    /// Quick toggle from the shopping list — mark purchased (defaulting the payer,
    /// since Stephanie is almost always the payer) or back to to-buy.
    func togglePurchased(_ e: Expense, defaultPayer: UUID?) async {
        var updated = e
        if e.isPurchased {
            updated.status = .notPurchased
        } else {
            updated.status = .purchased
            if updated.paidBy == nil { updated.paidBy = defaultPayer }
            if updated.spentOn == nil { updated.spentOn = Date() }
        }
        if let idx = expenses.firstIndex(where: { $0.id == e.id }) { expenses[idx] = updated }
        do {
            try await supabase.from("fam_trip_expenses").upsert(updated).execute()
        } catch { errorMessage = error.localizedDescription }
    }

    private func fetchReservations() async -> [Reservation] {
        do {
            return try await supabase.from("fam_reservations")
                .select().eq("trip_id", value: tripID)
                .order("sort").order("start_at", ascending: true, nullsFirst: false)
                .execute().value
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func fetchItinerary() async -> [ItineraryDay] {
        do {
            return try await supabase.from("fam_trip_itinerary")
                .select().eq("trip_id", value: tripID)
                .order("day_date").execute().value
        } catch {
            return []
        }
    }

    // MARK: Reservations

    func saveReservation(_ r: Reservation) async {
        do {
            try await supabase.from("fam_reservations").upsert(r).execute()
            await syncReservationToItinerary(r)   // mirrors check-in/out; reloads
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteReservation(_ r: Reservation) async {
        do {
            try await supabase.from("fam_reservations").delete().eq("id", value: r.id).execute()
            // Clear its auto-added itinerary entries (treat as a reservation with
            // no dates), which also reloads.
            var cleared = r; cleared.startAt = nil; cleared.endAt = nil
            await syncReservationToItinerary(cleared)
        } catch { errorMessage = error.localizedDescription }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Mirrors a reservation's start/end datetimes into the itinerary as
    /// check-in / check-out activities. Idempotent: activities are keyed by the
    /// reservation id, so editing a reservation updates (not duplicates) them,
    /// and clearing its dates removes them. Days emptied by removal are deleted.
    func syncReservationToItinerary(_ r: Reservation) async {
        let cal = Calendar.current
        var desired: [(date: Date, activity: ItineraryActivity)] = []
        if let start = r.startAt {
            desired.append((cal.startOfDay(for: start),
                ItineraryActivity(time: Self.clockFormatter.string(from: start),
                                  title: "\(r.type.startLabel): \(r.title)",
                                  locationName: r.address?.nilIfBlank,
                                  reservationID: r.id)))
        }
        if let end = r.endAt {
            desired.append((cal.startOfDay(for: end),
                ItineraryActivity(time: Self.clockFormatter.string(from: end),
                                  title: "\(r.type.endLabel): \(r.title)",
                                  locationName: r.address?.nilIfBlank,
                                  reservationID: r.id)))
        }

        var days = itinerary
        let hadReservation = Set(days.filter { $0.activities.contains { $0.reservationID == r.id } }.map(\.id))
        for i in days.indices { days[i].activities.removeAll { $0.reservationID == r.id } }

        var touched = Set<UUID>()
        for item in desired {
            if let idx = days.firstIndex(where: { cal.isDate($0.dayDate, inSameDayAs: item.date) }) {
                days[idx].activities.append(item.activity)
                touched.insert(days[idx].id)
            } else {
                let newDay = ItineraryDay(tripID: tripID, dayDate: item.date, activities: [item.activity])
                days.append(newDay)
                touched.insert(newDay.id)
            }
        }

        // Persist days we added to, plus days we removed from that still have
        // other activities; delete days left empty by the removal.
        let toUpsert = days.filter { touched.contains($0.id) || (hadReservation.contains($0.id) && !$0.activities.isEmpty) }
        let toDelete = days.filter { hadReservation.contains($0.id) && $0.activities.isEmpty && !touched.contains($0.id) }
        guard !toUpsert.isEmpty || !toDelete.isEmpty else { await load(); return }
        do {
            if !toUpsert.isEmpty { try await supabase.from("fam_trip_itinerary").upsert(toUpsert).execute() }
            for day in toDelete { try await supabase.from("fam_trip_itinerary").delete().eq("id", value: day.id).execute() }
        } catch { errorMessage = error.localizedDescription }
        await load()
    }

    var reservationsByType: [(type: ReservationType, items: [Reservation])] {
        ReservationType.allCases.compactMap { type in
            let items = reservations.filter { $0.type == type }
            return items.isEmpty ? nil : (type, items)
        }
    }

    // MARK: Itinerary

    func saveDay(_ day: ItineraryDay) async {
        do {
            try await supabase.from("fam_trip_itinerary").upsert(day).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteDay(_ day: ItineraryDay) async {
        do {
            try await supabase.from("fam_trip_itinerary").delete().eq("id", value: day.id).execute()
            itinerary.removeAll { $0.id == day.id }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Every activity grouped by calendar day and sorted by time — the timeline
    /// display model. Merges duplicate day rows for the same date into one group.
    var itineraryTimeline: [ItineraryDayGroup] {
        let cal = Calendar.current
        var byDate: [Date: [ItineraryEntry]] = [:]
        for day in itinerary {
            let key = cal.startOfDay(for: day.dayDate)
            for act in day.activities {
                byDate[key, default: []].append(ItineraryEntry(activity: act, dayID: day.id))
            }
        }
        return byDate.keys.sorted().map { date in
            let all = byDate[date]!
            // Once the day is manually ordered (any activity has a sort), honor
            // that; otherwise fall back to chronological (time) order.
            let manual = all.contains { $0.activity.sort != nil }
            let entries = manual
                ? all.sorted { ($0.activity.sort ?? .max) < ($1.activity.sort ?? .max) }
                : all.sorted { ItineraryTime.sortValue($0.activity.time) < ItineraryTime.sortValue($1.activity.time) }
            return ItineraryDayGroup(date: date, entries: entries)
        }
    }

    /// Persists a manual reorder for a day: moves the dragged activities to sit
    /// just before `target`, assigns explicit sort indices, and consolidates the
    /// date's activities into a single row.
    func reorderDay(date: Date, moving draggedIDs: [String], before target: UUID) async {
        let cal = Calendar.current
        guard let group = itineraryTimeline.first(where: { cal.isDate($0.date, inSameDayAs: date) }) else { return }
        var ordered = group.entries.map(\.activity)
        let dragged = Set(draggedIDs)
        let moving = ordered.filter { dragged.contains($0.id.uuidString) }
        guard !moving.isEmpty, !moving.contains(where: { $0.id == target }) else { return }
        ordered.removeAll { dragged.contains($0.id.uuidString) }
        if let idx = ordered.firstIndex(where: { $0.id == target }) {
            ordered.insert(contentsOf: moving, at: idx)
        } else {
            ordered.append(contentsOf: moving)
        }
        for i in ordered.indices { ordered[i].sort = i }
        await consolidate(date: date, activities: ordered)
    }

    /// Writes all of a date's activities into a single day row and removes any
    /// duplicate rows for that date.
    private func consolidate(date: Date, activities: [ItineraryActivity]) async {
        let cal = Calendar.current
        let rows = itinerary.filter { cal.isDate($0.dayDate, inSameDayAs: date) }
        let day = ItineraryDay(id: rows.first?.id ?? UUID(), tripID: tripID,
                               dayDate: cal.startOfDay(for: date), activities: activities)
        do {
            try await supabase.from("fam_trip_itinerary").upsert(day).execute()
            for extra in rows.dropFirst() {
                try await supabase.from("fam_trip_itinerary").delete().eq("id", value: extra.id).execute()
            }
        } catch { errorMessage = error.localizedDescription }
        await load()
    }

    var hasItinerary: Bool { itinerary.contains { !$0.activities.isEmpty } }

    /// Adds or updates a single activity, placing it on `date`'s day (creating the
    /// day row if needed, reusing an existing one otherwise — so we never spawn
    /// duplicate day rows). If the activity moved to a new date, it's removed from
    /// its old row (deleting that row if it's now empty).
    func upsertActivity(_ activity: ItineraryActivity, onDate date: Date, fromDayID: UUID?) async {
        let cal = Calendar.current
        var days = itinerary
        var affected = Set<UUID>()

        if let fromDayID, let i = days.firstIndex(where: { $0.id == fromDayID }),
           !cal.isDate(days[i].dayDate, inSameDayAs: date) {
            days[i].activities.removeAll { $0.id == activity.id }
            affected.insert(days[i].id)
        }

        if let i = days.firstIndex(where: { cal.isDate($0.dayDate, inSameDayAs: date) }) {
            if let a = days[i].activities.firstIndex(where: { $0.id == activity.id }) {
                days[i].activities[a] = activity
            } else {
                days[i].activities.append(activity)
            }
            affected.insert(days[i].id)
        } else {
            let day = ItineraryDay(tripID: tripID, dayDate: cal.startOfDay(for: date), activities: [activity])
            days.append(day)
            affected.insert(day.id)
        }
        await persist(days: days, affected: affected)
    }

    func deleteActivity(id: UUID, fromDayID: UUID) async {
        guard let i = itinerary.firstIndex(where: { $0.id == fromDayID }) else { return }
        var days = itinerary
        days[i].activities.removeAll { $0.id == id }
        await persist(days: days, affected: [days[i].id])
    }

    /// Upserts affected non-empty day rows, deletes emptied ones, then reloads.
    private func persist(days: [ItineraryDay], affected: Set<UUID>) async {
        let upserts = days.filter { affected.contains($0.id) && !$0.activities.isEmpty }
        let deletes = days.filter { affected.contains($0.id) && $0.activities.isEmpty }
        do {
            if !upserts.isEmpty { try await supabase.from("fam_trip_itinerary").upsert(upserts).execute() }
            for d in deletes { try await supabase.from("fam_trip_itinerary").delete().eq("id", value: d.id).execute() }
        } catch { errorMessage = error.localizedDescription }
        await load()
    }

    // MARK: Packing

    private func fetchPacking() async -> [PackingItem] {
        do {
            return try await supabase.from("fam_trip_packing")
                .select().eq("trip_id", value: tripID).order("item").execute().value
        } catch { return [] }
    }

    func savePacking(_ item: PackingItem) async {
        do {
            try await supabase.from("fam_trip_packing").upsert(item).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Optimistic check toggle — flips locally, then persists.
    func togglePacking(_ item: PackingItem) async {
        var updated = item
        updated.checked.toggle()
        if let idx = packing.firstIndex(where: { $0.id == item.id }) { packing[idx] = updated }
        do {
            try await supabase.from("fam_trip_packing")
                .update(["checked": updated.checked]).eq("id", value: item.id).execute()
        } catch { errorMessage = error.localizedDescription }
    }

    func deletePacking(_ item: PackingItem) async {
        do {
            try await supabase.from("fam_trip_packing").delete().eq("id", value: item.id).execute()
            packing.removeAll { $0.id == item.id }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Applies a template's items to this trip for each member in `memberIDs`,
    /// skipping items a member already has (case-insensitive name match). Returns
    /// the number of rows added.
    @discardableResult
    func applyTemplate(items templateItems: [(item: String, category: String?)],
                       to memberIDs: [UUID]) async -> Int {
        guard !templateItems.isEmpty, !memberIDs.isEmpty else { return 0 }
        var rows: [PackingItem] = []
        for memberID in memberIDs {
            let existing = Set(packing.filter { $0.memberID == memberID }.map { $0.item.lowercased() })
            for t in templateItems where !existing.contains(t.item.lowercased()) {
                rows.append(PackingItem(tripID: tripID, memberID: memberID, item: t.item, category: t.category))
            }
        }
        guard !rows.isEmpty else { return 0 }
        do {
            try await supabase.from("fam_trip_packing").insert(rows).execute()
            await load()
            return rows.count
        } catch { errorMessage = error.localizedDescription; return 0 }
    }

    // MARK: Expenses + splits

    private func fetchExpenses() async -> [Expense] {
        do {
            return try await supabase.from("fam_trip_expenses")
                .select().eq("trip_id", value: tripID).order("logged_at", ascending: false).execute().value
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func fetchSplits(for expenseIDs: [UUID]) async -> [ExpenseSplit] {
        guard !expenseIDs.isEmpty else { return [] }
        do {
            return try await supabase.from("fam_expense_splits")
                .select().in("expense_id", values: expenseIDs.map(\.uuidString)).execute().value
        } catch { return [] }
    }

    /// Saves an expense and replaces its splits atomically enough for a family app
    /// (upsert expense, delete old splits, insert new ones), then reloads.
    func saveExpense(_ expense: Expense, splits newSplits: [ExpenseSplit]) async {
        do {
            try await supabase.from("fam_trip_expenses").upsert(expense).execute()
            try await supabase.from("fam_expense_splits").delete().eq("expense_id", value: expense.id).execute()
            if !newSplits.isEmpty {
                try await supabase.from("fam_expense_splits").insert(newSplits).execute()
            }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteExpense(_ expense: Expense) async {
        do {
            try await supabase.from("fam_trip_expenses").delete().eq("id", value: expense.id).execute()
            expenses.removeAll { $0.id == expense.id }
            splits.removeAll { $0.expenseID == expense.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func splits(for expense: Expense) -> [ExpenseSplit] {
        splits.filter { $0.expenseID == expense.id }
    }

    // MARK: Documents

    private func fetchDocuments() async -> [TripDocument] {
        do {
            return try await supabase.from("fam_trip_documents")
                .select().eq("trip_id", value: tripID).order("created_at", ascending: false).execute().value
        } catch { return [] }
    }

    /// Uploads a file to the trip-docs bucket and records it. Path is
    /// <family_id>/<trip_id>/<uuid>.<ext> so Storage RLS scopes by family.
    func addDocument(familyID: UUID, data: Data, fileName: String, contentType: String,
                     kind: DocumentKind, reservationID: UUID? = nil, createdBy: UUID?) async {
        let ext = (fileName as NSString).pathExtension.isEmpty ? "dat" : (fileName as NSString).pathExtension
        let docID = UUID()
        // Lowercase to match the case-insensitive storage RLS on the family-id segment.
        let path = "\(familyID.uuidString.lowercased())/\(tripID.uuidString.lowercased())/\(docID.uuidString.lowercased()).\(ext)"
        do {
            try await StorageService.upload(path: path, data: data, contentType: contentType)
            var doc = TripDocument(id: docID, familyID: familyID, tripID: tripID, reservationID: reservationID,
                                   kind: kind, storagePath: path, fileName: fileName, contentType: contentType,
                                   title: fileName, createdBy: createdBy)
            doc.isSensitive = (kind == .passport)
            try await supabase.from("fam_trip_documents").insert(doc).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Adds a link resource (no file upload).
    func addLink(familyID: UUID, url: String, title: String?, createdBy: UUID?) async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let doc = TripDocument(familyID: familyID, tripID: tripID, kind: .link, url: normalized,
                               title: title?.nilIfBlank, createdBy: createdBy)
        do {
            try await supabase.from("fam_trip_documents").insert(doc).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteDocument(_ doc: TripDocument) async {
        do {
            if let path = doc.storagePath { try? await StorageService.remove(path: path) }
            try await supabase.from("fam_trip_documents").delete().eq("id", value: doc.id).execute()
            documents.removeAll { $0.id == doc.id }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Copies the reusable sub-items (packing, shopping list, itinerary) to a new
    /// trip — checks/statuses reset. Reservations & expenses are trip-specific and
    /// not copied.
    func copyReusableItems(to newTripID: UUID) async {
        let newPacking = packing.map {
            PackingItem(tripID: newTripID, memberID: $0.memberID, item: $0.item,
                        checked: false, autoSuggested: $0.autoSuggested, category: $0.category)
        }
        if !newPacking.isEmpty { try? await supabase.from("fam_trip_packing").insert(newPacking).execute() }

        let newShopping = shoppingItems.map {
            Expense(tripID: newTripID, category: $0.category, description: $0.description,
                    amount: $0.amount, status: .notPurchased, tag: $0.tag, link: $0.link,
                    purchasedFrom: $0.purchasedFrom, notes: $0.notes)
        }
        if !newShopping.isEmpty { try? await supabase.from("fam_trip_expenses").insert(newShopping).execute() }

        let newDays = itinerary.map { day -> ItineraryDay in
            ItineraryDay(tripID: newTripID, dayDate: day.dayDate,
                         activities: day.activities.map { act in
                             var a = act; a.id = UUID(); a.done = false; return a
                         })
        }
        if !newDays.isEmpty { try? await supabase.from("fam_trip_itinerary").insert(newDays).execute() }
    }

    /// Actual spend — purchased items only.
    var tripTotal: Double { purchasedExpenses.reduce(0) { $0 + $1.amount } }
    /// Actual + not-yet-purchased (projected) spend.
    var projectedTotal: Double { expenses.reduce(0) { $0 + $1.amount } }

    /// Splits belonging to purchased items (shopping items don't settle up).
    private var purchasedSplits: [ExpenseSplit] {
        let ids = Set(purchasedExpenses.map(\.id))
        return splits.filter { ids.contains($0.expenseID) }
    }

    /// Per-member owed totals across purchased splits.
    var perMemberTotals: [(memberID: UUID, amount: Double)] {
        Dictionary(grouping: purchasedSplits, by: \.memberID)
            .map { (memberID: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    /// Who-owes-whom: nets each member's paid vs. their split share, then greedily
    /// matches debtors to creditors into the fewest transfers.
    func settleUp() -> [(from: UUID, to: UUID, amount: Double)] {
        var paid: [UUID: Double] = [:]
        for e in purchasedExpenses { if let p = e.paidBy { paid[p, default: 0] += e.amount } }
        var owes: [UUID: Double] = [:]
        for s in purchasedSplits { owes[s.memberID, default: 0] += s.amount }

        let ids = Set(paid.keys).union(owes.keys)
        var creditors = ids.map { (id: $0, amt: (paid[$0] ?? 0) - (owes[$0] ?? 0)) }
            .filter { $0.amt > 0.01 }.sorted { $0.amt > $1.amt }
        var debtors = ids.map { (id: $0, amt: (owes[$0] ?? 0) - (paid[$0] ?? 0)) }
            .filter { $0.amt > 0.01 }.sorted { $0.amt > $1.amt }

        var transfers: [(from: UUID, to: UUID, amount: Double)] = []
        var ci = 0, di = 0
        while ci < creditors.count && di < debtors.count {
            let pay = min(creditors[ci].amt, debtors[di].amt)
            transfers.append((from: debtors[di].id, to: creditors[ci].id, amount: pay))
            creditors[ci].amt -= pay; debtors[di].amt -= pay
            if creditors[ci].amt < 0.01 { ci += 1 }
            if debtors[di].amt < 0.01 { di += 1 }
        }
        return transfers
    }
}
