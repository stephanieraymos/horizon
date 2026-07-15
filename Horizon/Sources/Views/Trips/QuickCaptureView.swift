import SwiftUI

/// Quick Capture — dictate or type a free-form note ("bring sandals for myself,
/// buy apples at Walmart, charge the car the night before we leave") and Claude
/// routes it into this trip's packing list, checklist, and shopping list. Every
/// parsed item lands in an editable review screen before anything is saved.
struct QuickCaptureView: View {
    let store: TripDetailStore
    let trip: Trip
    let familyID: UUID

    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case input, loading, review, failed }
    @State private var phase: Phase = .input
    @State private var text = ""
    @State private var errorText = ""
    @State private var isSaving = false

    @State private var packingDrafts: [PackingDraft] = []
    @State private var todoDrafts: [TodoDraft] = []
    @State private var shoppingDrafts: [ShoppingDraft] = []

    // MARK: Drafts

    private struct PackingDraft: Identifiable {
        let id = UUID(); var item: String; var memberID: UUID?; var include = true
    }
    private struct TodoDraft: Identifiable {
        let id = UUID(); var title: String; var dueDate: Date?; var include = true
    }
    private struct ShoppingDraft: Identifiable {
        let id = UUID(); var item: String; var store: String?; var include = true
    }

    private var totalToAdd: Int {
        packingDrafts.filter(\.include).count
            + todoDrafts.filter(\.include).count
            + shoppingDrafts.filter(\.include).count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:   inputView
                case .loading: loadingView
                case .review:  reviewView
                case .failed:  failedView
                }
            }
            .navigationTitle(phase == .review ? "Review" : "Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if phase == .input {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Parse") { Task { await runParse() } }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(totalToAdd)") { Task { await addAll() } }
                            .disabled(totalToAdd == 0 || isSaving)
                    }
                }
            }
        }
    }

    // MARK: Input

    private var inputView: some View {
        Form {
            Section {
                TextField("Say or type what to add…", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.body)
            } header: {
                Text("Tap the mic on your keyboard to dictate")
            } footer: {
                Text("e.g. “Bring sandals for myself, pack sunscreen and sunglasses, remember to charge the car to 80% the night before we leave, and buy apples and pears at Walmart.”")
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading your note…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("Couldn’t parse that", systemImage: "exclamationmark.triangle")
        } description: {
            Text(errorText)
        } actions: {
            Button("Try again") { phase = .input }
        }
    }

    // MARK: Review

    private var reviewView: some View {
        Form {
            if packingDrafts.isEmpty && todoDrafts.isEmpty && shoppingDrafts.isEmpty {
                ContentUnavailableView("Nothing to add", systemImage: "tray",
                                       description: Text("The note didn’t contain any items. Go back and try rephrasing."))
            }
            if !packingDrafts.isEmpty {
                Section("Packing") {
                    ForEach($packingDrafts) { $d in
                        HStack(spacing: 10) {
                            includeButton($d.include)
                            TextField("Item", text: $d.item)
                            Spacer(minLength: 4)
                            personMenu($d.memberID)
                        }
                        .opacity(d.include ? 1 : 0.4)
                    }
                }
            }
            if !todoDrafts.isEmpty {
                Section("Checklist") {
                    ForEach($todoDrafts) { $d in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                includeButton($d.include)
                                TextField("Task", text: $d.title)
                            }
                            dueControl($d.dueDate)
                                .padding(.leading, 30)
                        }
                        .opacity(d.include ? 1 : 0.4)
                    }
                }
            }
            if !shoppingDrafts.isEmpty {
                Section("Shopping") {
                    ForEach($shoppingDrafts) { $d in
                        HStack(spacing: 10) {
                            includeButton($d.include)
                            TextField("Item", text: $d.item)
                            Spacer(minLength: 4)
                            storeMenu($d.store)
                        }
                        .opacity(d.include ? 1 : 0.4)
                    }
                }
            }
        }
    }

    private func includeButton(_ include: Binding<Bool>) -> some View {
        Button {
            include.wrappedValue.toggle()
        } label: {
            Image(systemName: include.wrappedValue ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(include.wrappedValue ? Theme.Colors.brand : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func personMenu(_ memberID: Binding<UUID?>) -> some View {
        Menu {
            Button { memberID.wrappedValue = nil } label: {
                Label("Everyone", systemImage: memberID.wrappedValue == nil ? "checkmark" : "person.2")
            }
            ForEach(family.members) { m in
                Button { memberID.wrappedValue = m.id } label: {
                    Label(m.name, systemImage: memberID.wrappedValue == m.id ? "checkmark" : "person")
                }
            }
        } label: {
            Text(memberID.wrappedValue.flatMap { family.memberName(id: $0) } ?? "Everyone")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.Colors.brand)
        }
    }

    @ViewBuilder
    private func dueControl(_ dueDate: Binding<Date?>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary)
            if let unwrapped = dueDate.wrappedValue {
                DatePicker("", selection: Binding(get: { unwrapped },
                                                  set: { dueDate.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                Button { dueDate.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Add due date") {
                    dueDate.wrappedValue = trip.departDate ?? Date()
                }
                .font(.caption)
            }
        }
    }

    private func storeMenu(_ storeName: Binding<String?>) -> some View {
        let isNew = storeName.wrappedValue.flatMap { trips.store(named: $0) } == nil
            && (storeName.wrappedValue?.nilIfBlank != nil)
        return Menu {
            Button { storeName.wrappedValue = nil } label: {
                Label("No store", systemImage: storeName.wrappedValue == nil ? "checkmark" : "xmark")
            }
            if let s = storeName.wrappedValue?.nilIfBlank, isNew {
                Button { /* keep as-is */ } label: {
                    Label("Create “\(s)”", systemImage: "checkmark")
                }
            }
            Divider()
            ForEach(trips.shoppingStores) { st in
                Button { storeName.wrappedValue = st.name } label: {
                    Label(st.name, systemImage: storeName.wrappedValue == st.name ? "checkmark" : "storefront")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(storeName.wrappedValue?.nilIfBlank ?? "Store")
                if isNew { Text("• new").foregroundStyle(.orange) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.Colors.brand)
        }
    }

    // MARK: Parse + resolve

    private func runParse() async {
        phase = .loading
        let ctx = CaptureParser.Context(
            travelers: family.members.map(\.name),
            currentMemberName: family.currentMember?.name,
            stores: trips.shoppingStores.map(\.name),
            packingCategories: trips.packingCategories.map(\.name),
            departDate: CaptureParser.isoDay(trip.departDate),
            returnDate: CaptureParser.isoDay(trip.returnDate),
            tripName: trip.name)
        do {
            let parsed = try await CaptureParser.parse(text: text, context: ctx)
            packingDrafts = parsed.packing.map { PackingDraft(item: $0.item, memberID: resolvePerson($0.person)) }
            todoDrafts = parsed.todos.map { TodoDraft(title: $0.title, dueDate: resolveDue($0.due)) }
            shoppingDrafts = parsed.shopping.map { ShoppingDraft(item: $0.item, store: resolveStore($0.store)) }
            phase = .review
        } catch {
            errorText = friendlyError(error)
            phase = .failed
        }
    }

    private func resolvePerson(_ name: String) -> UUID? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if ["me", "myself", "i", "mine", "my"].contains(n) { return family.currentMember?.id }
        if ["everyone", "everybody", "all", "us", "we", ""].contains(n) { return nil }
        return family.members.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }

    private func resolveDue(_ due: ParsedDue?) -> Date? {
        guard let due else { return nil }
        if let iso = due.date?.nilIfBlank, let d = Self.parseISODay(iso) { return d }
        let cal = Calendar(identifier: .gregorian)
        switch due.anchor {
        case "departure":
            guard let base = trip.departDate else { return nil }
            return cal.date(byAdding: .day, value: due.offsetDays, to: base)
        case "return":
            guard let base = trip.returnDate ?? trip.departDate else { return nil }
            return cal.date(byAdding: .day, value: due.offsetDays, to: base)
        default:
            return nil
        }
    }

    /// Returns the canonical stored name if the store already exists, otherwise
    /// the parsed name as-is (flagged "new" in the picker, created on save).
    private func resolveStore(_ name: String?) -> String? {
        guard let name = name?.nilIfBlank else { return nil }
        return trips.store(named: name)?.name ?? name
    }

    private static func parseISODay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func friendlyError(_ error: Error) -> String {
        let s = "\(error)"
        if s.localizedCaseInsensitiveContains("ANTHROPIC_API_KEY") {
            return "The parser isn’t configured yet (missing API key). See setup notes."
        }
        return "Something went wrong reaching the parser. Check your connection and try again."
    }

    // MARK: Apply

    private func addAll() async {
        isSaving = true
        defer { isSaving = false }

        for d in packingDrafts where d.include {
            let item = d.item.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            await store.savePacking(PackingItem(tripID: store.tripID, memberID: d.memberID, item: item))
        }

        var sort = store.todos.count
        for d in todoDrafts where d.include {
            let title = d.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            await store.saveTodo(TripTodo(tripID: store.tripID, familyID: familyID, title: title,
                                          dueDate: d.dueDate, sort: sort,
                                          createdBy: family.currentMember?.userID))
            sort += 1
        }

        for d in shoppingDrafts where d.include {
            let item = d.item.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            let storeName = d.store?.nilIfBlank
            if let s = storeName, trips.store(named: s) == nil {
                await trips.createShoppingStore(familyID: familyID, name: s)
            }
            let expense = Expense(tripID: store.tripID,
                                  category: ExpenseCategory.merch.rawValue,
                                  description: item, status: .notPurchased,
                                  purchasedFrom: storeName)
            await store.saveExpense(expense, splits: [])
        }

        dismiss()
    }
}
