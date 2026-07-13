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

    /// Optimistic status cycle (To buy → In cart → Purchased → …).
    func cyclePurchase(_ p: TripPurchase) async {
        var updated = p
        updated.status = p.status.next
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
                     kind: DocumentKind, createdBy: UUID?) async {
        let ext = (fileName as NSString).pathExtension.isEmpty ? "dat" : (fileName as NSString).pathExtension
        let docID = UUID()
        let path = "\(familyID.uuidString)/\(tripID.uuidString)/\(docID.uuidString).\(ext)"
        do {
            try await StorageService.upload(path: path, data: data, contentType: contentType)
            var doc = TripDocument(id: docID, familyID: familyID, tripID: tripID, kind: kind,
                                   storagePath: path, fileName: fileName, contentType: contentType,
                                   title: fileName, createdBy: createdBy)
            doc.isSensitive = (kind == .passport)
            try await supabase.from("fam_trip_documents").insert(doc).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteDocument(_ doc: TripDocument) async {
        do {
            try? await StorageService.remove(path: doc.storagePath)
            try await supabase.from("fam_trip_documents").delete().eq("id", value: doc.id).execute()
            documents.removeAll { $0.id == doc.id }
        } catch { errorMessage = error.localizedDescription }
    }

    var tripTotal: Double { expenses.reduce(0) { $0 + $1.amount } }

    /// Per-member owed totals across all splits.
    var perMemberTotals: [(memberID: UUID, amount: Double)] {
        Dictionary(grouping: splits, by: \.memberID)
            .map { (memberID: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
}
