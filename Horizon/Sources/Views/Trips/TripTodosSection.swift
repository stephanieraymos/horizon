import SwiftUI

/// Pre-trip checklist — tasks with optional due dates (book rental, renew
/// passport, arrange pet sitter), separate from the packing list.
struct TripTodosSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family

    @State private var showAdd = false
    @State private var editing: TripTodo?

    private var remaining: Int { store.todos.filter { !$0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Checklist").font(.title3.bold())
                if !store.todos.isEmpty {
                    Text("\(remaining) left")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if store.todos.isEmpty {
                Text("Add pre-trip to-dos — book the rental, renew passports, arrange a sitter.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(store.todos) { todo in
                    TodoRow(todo: todo,
                            onToggle: { Task { await store.toggleTodo(todo) } },
                            onEdit: { editing = todo })
                        .contextMenu {
                            Button("Edit") { editing = todo }
                            Button("Delete", role: .destructive) { Task { await store.deleteTodo(todo) } }
                        }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            TodoAddView(store: store, familyID: familyID, existing: nil)
        }
        .sheet(item: $editing) { todo in
            TodoAddView(store: store, familyID: familyID, existing: todo)
        }
    }
}

private struct TodoRow: View {
    let todo: TripTodo
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var overdue: Bool {
        guard let due = todo.dueDate, !todo.done else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.done ? Theme.Colors.brand : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todo.title)
                            .strikethrough(todo.done)
                            .foregroundStyle(todo.done ? .secondary : .primary)
                        if let due = todo.dueDate {
                            Text(due, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption)
                                .foregroundStyle(overdue ? .red : .secondary)
                        }
                    }
                    Spacer()
                    if overdue {
                        Text("Overdue").font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}

private struct TodoAddView: View {
    let store: TripDetailStore
    let familyID: UUID
    let existing: TripTodo?
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date

    init(store: TripDetailStore, familyID: UUID, existing: TripTodo?) {
        self.store = store; self.familyID = familyID; self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _hasDue = State(initialValue: existing?.dueDate != nil)
        _due = State(initialValue: existing?.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task (e.g. Book rental car)", text: $title)
                Section {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") {
                        // Preserve done/sort/createdBy when editing; upsert by id.
                        let todo = TripTodo(id: existing?.id ?? UUID(),
                                            tripID: store.tripID, familyID: familyID,
                                            title: title.trimmingCharacters(in: .whitespaces),
                                            done: existing?.done ?? false,
                                            dueDate: hasDue ? due : nil,
                                            sort: existing?.sort ?? store.todos.count,
                                            createdBy: existing?.createdBy ?? family.currentMember?.userID)
                        Task { await store.saveTodo(todo); dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
