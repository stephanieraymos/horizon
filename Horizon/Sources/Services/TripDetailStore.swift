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
    var purchases: [TripPurchase] = []
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
        purchases = await fetchPurchases()
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

    // MARK: Purchases (shopping list)

    private func fetchPurchases() async -> [TripPurchase] {
        do {
            return try await supabase.from("fam_trip_purchases")
                .select().eq("trip_id", value: tripID).order("name").execute().value
        } catch { return [] }
    }

    func savePurchase(_ p: TripPurchase) async {
        do {
            try await supabase.from("fam_trip_purchases").upsert(p).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Tapping an item checks it off as Purchased (or back to To buy). "In cart"
    /// is a deliberate choice set in the editor, not part of the quick toggle.
    func togglePurchased(_ p: TripPurchase) async {
        var updated = p
        updated.status = (p.status == .purchased) ? .notPurchased : .purchased
        if let idx = purchases.firstIndex(where: { $0.id == p.id }) { purchases[idx] = updated }
        do {
            try await supabase.from("fam_trip_purchases")
                .update(["status": updated.status.rawValue]).eq("id", value: p.id).execute()
        } catch { errorMessage = error.localizedDescription }
    }

    func deletePurchase(_ p: TripPurchase) async {
        do {
            try await supabase.from("fam_trip_purchases").delete().eq("id", value: p.id).execute()
            purchases.removeAll { $0.id == p.id }
        } catch { errorMessage = error.localizedDescription }
    }

    var purchasesByTag: [(tag: String, items: [TripPurchase])] {
        Dictionary(grouping: purchases, by: { $0.tag?.nilIfBlank ?? "Other" })
            .map { (tag: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.tag < $1.tag }
    }

    var purchaseTags: [String] {
        Array(Set(purchases.compactMap { $0.tag?.nilIfBlank })).sorted()
    }

    var purchasesToBuy: Int { purchases.filter { $0.status != .purchased }.count }
    var purchasesSpent: Double {
        purchases.filter { $0.status == .purchased }.compactMap(\.amountDollars).reduce(0, +)
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
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteReservation(_ r: Reservation) async {
        do {
            try await supabase.from("fam_reservations").delete().eq("id", value: r.id).execute()
            reservations.removeAll { $0.id == r.id }
        } catch { errorMessage = error.localizedDescription }
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

        let newPurchases = purchases.map {
            TripPurchase(familyID: $0.familyID, tripID: newTripID, name: $0.name,
                         amountCents: $0.amountCents, status: .notPurchased, tag: $0.tag,
                         purchasedFrom: $0.purchasedFrom)
        }
        if !newPurchases.isEmpty { try? await supabase.from("fam_trip_purchases").insert(newPurchases).execute() }

        let newDays = itinerary.map { day -> ItineraryDay in
            ItineraryDay(tripID: newTripID, dayDate: day.dayDate,
                         activities: day.activities.map { act in
                             var a = act; a.id = UUID(); a.done = false; return a
                         })
        }
        if !newDays.isEmpty { try? await supabase.from("fam_trip_itinerary").insert(newDays).execute() }
    }

    var tripTotal: Double { expenses.reduce(0) { $0 + $1.amount } }

    /// Per-member owed totals across all splits.
    var perMemberTotals: [(memberID: UUID, amount: Double)] {
        Dictionary(grouping: splits, by: \.memberID)
            .map { (memberID: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    /// Who-owes-whom: nets each member's paid vs. their split share, then greedily
    /// matches debtors to creditors into the fewest transfers.
    func settleUp() -> [(from: UUID, to: UUID, amount: Double)] {
        var paid: [UUID: Double] = [:]
        for e in expenses { if let p = e.paidBy { paid[p, default: 0] += e.amount } }
        var owes: [UUID: Double] = [:]
        for s in splits { owes[s.memberID, default: 0] += s.amount }

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
