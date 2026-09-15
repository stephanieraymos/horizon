import SwiftUI
import AppShellKit

/// Days · hours · minutes · seconds to `target`, ticking once a second. Shared
/// by a countdown's detail screen and a plan's detail header.
///
/// Without a set time the target is the start of the day, and the caption says
/// so — the number is only as exact as the time behind it.
struct LiveCountdown: View {
    let target: Date
    var tint: Color = Theme.Colors.brand
    /// False when no time is set, so the caption can say it's counting to midnight.
    var hasExactTime: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 10) {
                if target > now {
                    // The clock she pointed at (2026-09-14): big digit groups split
                    // by colons, tiny unit letters underneath — "06:15:27:54".
                    ClockDigits(parts: Self.parts(from: now, to: target), size: 44,
                                colon: tint.opacity(0.7))
                    Text(hasExactTime
                         ? "Until \(target.formatted(date: .abbreviated, time: .shortened))"
                         : "Until the start of \(target.formatted(date: .abbreviated, time: .omitted)) — set a time to count to the minute")
                        .font(.caption)
                        .foregroundStyle(FamilyPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                } else if Calendar.current.isDate(target, inSameDayAs: now) {
                    Text("It's today 🎉")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(tint)
                    if hasExactTime {
                        Text("Started \(target.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(FamilyPalette.inkSecondary)
                    }
                } else {
                    Text("\(target.formatted(.relative(presentation: .named)))")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(FamilyPalette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.18)))
    }

    struct Parts: Equatable { var days, hours, minutes, seconds: Int }

    /// Calendar-aware split, so a daylight-saving change doesn't show "23 hours"
    /// the night the clocks move.
    static func parts(from now: Date, to target: Date) -> Parts {
        let c = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: now, to: target)
        return Parts(days: max(c.day ?? 0, 0), hours: max(c.hour ?? 0, 0),
                     minutes: max(c.minute ?? 0, 0), seconds: max(c.second ?? 0, 0))
    }

}

/// Pick an exact time, or clear it back to all day.
struct TimeOfDaySheet: View {
    let title: String
    let current: String?
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(title: String, current: String?, onSave: @escaping (String?) -> Void) {
        self.title = title
        self.current = current
        self.onSave = onSave
        _time = State(initialValue: TimeOfDay.pickerDate(current))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("The countdown ticks to this exact time. Without one it counts to the start of the day.")
                }
                if current != nil {
                    Section {
                        Button("Remove time (all day)", role: .destructive) {
                            onSave(nil); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(TimeOfDay.string(from: time)); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Write or edit a countdown's note.
struct CountdownNoteSheet: View {
    let title: String
    let current: String?
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, current: String?, onSave: @escaping (String?) -> Void) {
        self.title = title
        self.current = current
        self.onSave = onSave
        _text = State(initialValue: current ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Anything to remember — tickets, who's coming, what to bring…",
                              text: $text, axis: .vertical)
                        .lineLimit(4...14)
                        .focused($focused)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
