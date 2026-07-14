import Foundation
import Observation
import Supabase

/// Loads and edits reusable packing templates (`fam_packing_templates` +
/// `fam_packing_template_items`). Applying a template inserts rows into a trip's
/// `fam_trip_packing` for the chosen travelers.
@Observable
@MainActor
final class PackingTemplatesStore {
    private(set) var templates: [PackingTemplate] = []
    /// template_id → its items (loaded lazily / after edits).
    private(set) var itemsByTemplate: [UUID: [PackingTemplateItem]] = [:]
    var error: String?

    func load() async {
        do {
            templates = try await supabase.from("fam_packing_templates")
                .select().order("name").execute().value
        } catch { self.error = error.localizedDescription; return }
        await loadItems()
    }

    private func loadItems() async {
        do {
            let rows: [PackingTemplateItem] = try await supabase
                .from("fam_packing_template_items").select().order("sort").execute().value
            itemsByTemplate = Dictionary(grouping: rows, by: \.templateID)
        } catch { /* non-fatal */ }
    }

    func items(for templateID: UUID) -> [PackingTemplateItem] {
        (itemsByTemplate[templateID] ?? []).sorted { $0.sort < $1.sort }
    }

    // MARK: - Template CRUD

    @discardableResult
    func createTemplate(familyID: UUID, name: String, icon: String, createdBy: UUID?) async -> PackingTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let row: PackingTemplate = try await supabase.from("fam_packing_templates")
                .insert(PackingTemplate(familyID: familyID, name: trimmed, icon: icon, createdBy: createdBy))
                .select().single().execute().value
            templates.append(row); templates.sort { $0.name < $1.name }
            itemsByTemplate[row.id] = []
            return row
        } catch { self.error = error.localizedDescription; return nil }
    }

    func renameTemplate(_ template: PackingTemplate, name: String, icon: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        struct P: Encodable { let name: String; let icon: String; let updated_at: Date }
        do {
            try await supabase.from("fam_packing_templates")
                .update(P(name: trimmed, icon: icon, updated_at: Date())).eq("id", value: template.id).execute()
            if let i = templates.firstIndex(where: { $0.id == template.id }) {
                templates[i].name = trimmed; templates[i].icon = icon
                templates.sort { $0.name < $1.name }
            }
        } catch { self.error = error.localizedDescription }
    }

    func deleteTemplate(_ template: PackingTemplate) async {
        do {
            try await supabase.from("fam_packing_templates").delete().eq("id", value: template.id).execute()
            templates.removeAll { $0.id == template.id }
            itemsByTemplate.removeValue(forKey: template.id)
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Item CRUD

    func addItem(templateID: UUID, item: String, category: String?) async {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let sort = (itemsByTemplate[templateID]?.map(\.sort).max() ?? -1) + 1
        do {
            let row: PackingTemplateItem = try await supabase.from("fam_packing_template_items")
                .insert(PackingTemplateItem(templateID: templateID, item: trimmed, category: category, sort: sort))
                .select().single().execute().value
            itemsByTemplate[templateID, default: []].append(row)
        } catch { self.error = error.localizedDescription }
    }

    func deleteItem(_ item: PackingTemplateItem) async {
        do {
            try await supabase.from("fam_packing_template_items").delete().eq("id", value: item.id).execute()
            itemsByTemplate[item.templateID]?.removeAll { $0.id == item.id }
        } catch { self.error = error.localizedDescription }
    }

    /// Creates a template from an existing trip's packing items (deduped by name).
    @discardableResult
    func createTemplate(fromPacking packing: [PackingItem], familyID: UUID,
                        name: String, icon: String, createdBy: UUID?) async -> PackingTemplate? {
        guard let template = await createTemplate(familyID: familyID, name: name, icon: icon, createdBy: createdBy)
        else { return nil }
        var seen = Set<String>()
        var rows: [PackingTemplateItem] = []
        var sort = 0
        for p in packing {
            let key = p.item.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            rows.append(PackingTemplateItem(templateID: template.id, item: p.item, category: p.category, sort: sort))
            sort += 1
        }
        guard !rows.isEmpty else { return template }
        do {
            try await supabase.from("fam_packing_template_items").insert(rows).execute()
            itemsByTemplate[template.id] = rows
        } catch { self.error = error.localizedDescription }
        return template
    }
}
