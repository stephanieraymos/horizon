import SwiftUI
import AppShellKit

// The Countdowns screen's cards, after the design she pointed at on 2026-09-14:
// the photo full-bleed behind a dark film, a coloured edge, and the whole clock
// — days, hours, minutes, seconds — ticking on the card itself.

/// "6 : 15 : 27 : 54" with D / HR / MIN / S under each group.
struct ClockDigits: View {
    let parts: LiveCountdown.Parts
    var size: CGFloat = 44
    var digit: Color = FamilyPalette.ink
    var colon: Color = FamilyPalette.inkSecondary
    var label: Color = FamilyPalette.inkSecondary

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.05) {
            group(parts.days, "D", pad: false)
            separator
            group(parts.hours, "HR")
            separator
            group(parts.minutes, "MIN")
            separator
            group(parts.seconds, "S")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(parts.days) days, \(parts.hours) hours, \(parts.minutes) minutes, \(parts.seconds) seconds to go")
    }

    private func group(_ value: Int, _ unit: String, pad: Bool = true) -> some View {
        VStack(spacing: 1) {
            Text(pad ? String(format: "%02d", value) : "\(value)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(digit)
                .contentTransition(.numericText(countsDown: true))
            Text(unit)
                .font(.system(size: max(9, size * 0.24), weight: .semibold))
                .foregroundStyle(label)
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: size * 0.9, weight: .semibold, design: .rounded))
            .foregroundStyle(colon)
    }
}

/// A countdown as a card: photo (or its colour) behind a dark film, title and
/// date on top, the live clock underneath.
struct CountdownCard: View {
    let item: Countdown
    var large = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            // The film: enough to keep white text readable on a bright photo.
            LinearGradient(colors: [.black.opacity(item.cover == nil ? 0.05 : 0.30),
                                    .black.opacity(item.cover == nil ? 0.30 : 0.62)],
                           startPoint: .top, endPoint: .bottom)
            content
        }
        .frame(height: large ? 196 : 148)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            Rectangle().fill(item.tint).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var background: some View {
        if let cover = item.cover {
            AdjustableCoverImage(cover: cover, focus: item.coverFocus) { tintFill }
        } else {
            tintFill
        }
    }

    /// No photo: the countdown's own colour, with its symbol large and faint.
    private var tintFill: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: [item.tint.opacity(0.95), item.tint.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.systemImage)
                .font(.system(size: large ? 130 : 104, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .offset(x: 18, y: 12)
                .accessibilityHidden(true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let emoji = item.emoji {
                    Text(emoji).font(large ? .title3 : .headline)
                } else {
                    Image(systemName: item.systemImage).font(.subheadline.weight(.semibold))
                }
                Text(item.title)
                    .font(large ? .title3.weight(.bold) : .headline)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(item.badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            Text(CountdownFormat.subtitle(item))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
            clock
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .padding(.vertical, 14)
        .padding(.leading, 19)
        .padding(.trailing, 14)
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let target = item.moment
            if item.isHappeningNow {
                Text(CountdownFormat.longUnit(item).map { "Happening now · \($0)" } ?? "Happening now")
                    .font(.system(large ? .title2 : .title3, design: .rounded).weight(.bold))
            } else if target > context.date {
                ClockDigits(parts: LiveCountdown.parts(from: context.date, to: target),
                            size: large ? 40 : 28,
                            digit: .white, colon: .white.opacity(0.6), label: .white.opacity(0.78))
            } else {
                Text("It's today 🎉")
                    .font(.system(large ? .title2 : .title3, design: .rounded).weight(.bold))
            }
        }
    }
}

/// How much of this month or this year has gone, and the clock to its end.
/// Two ways to show the percent — a bar or a ring — switchable from the card's
/// long-press menu, remembered per card.
struct PeriodCard: View {
    enum Period: String { case month, year }

    let period: Period
    @AppStorage private var style: String

    init(period: Period) {
        self.period = period
        _style = AppStorage(wrappedValue: period == .month ? "bar" : "ring",
                            "countdowns.period.\(period.rawValue).style")
    }

    private var tint: Color { period == .month ? .orange : .cyan }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let span = Self.interval(period, containing: now)
            let fraction = Self.fraction(of: span, at: now)
            ZStack(alignment: .bottomLeading) {
                backdrop
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(period == .month ? "🌙" : "🌍").font(.headline)
                            Text(period == .month ? "This Month" : "This Year").font(.headline)
                        }
                        Text(rangeLabel(span))
                            .font(.caption).foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 0)
                        ClockDigits(parts: LiveCountdown.parts(from: now, to: span.end), size: 28,
                                    digit: .white, colon: .white.opacity(0.6), label: .white.opacity(0.78))
                        if style == "bar" {
                            HStack(spacing: 10) {
                                bar(fraction)
                                Text(percent(fraction)).font(.subheadline.weight(.bold)).monospacedDigit()
                            }
                            .padding(.top, 4)
                        }
                        Text(dayLabel(span, now: now))
                            .font(.caption2).foregroundStyle(.white.opacity(0.8))
                    }
                    if style == "ring" {
                        Spacer(minLength: 0)
                        ring(fraction)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .padding(.vertical, 14)
                .padding(.leading, 19)
                .padding(.trailing, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(period == .month ? "This month" : "This year"): \(percent(fraction)) gone, \(dayLabel(span, now: now))")
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Picker("Show the percent as", selection: $style) {
                Label("Bar", systemImage: "chart.bar.fill").tag("bar")
                Label("Ring", systemImage: "circle.circle").tag("ring")
            }
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: period == .month
                           ? [Color(red: 0.16, green: 0.14, blue: 0.24), Color(red: 0.05, green: 0.05, blue: 0.09)]
                           : [Color(red: 0.03, green: 0.15, blue: 0.28), Color(red: 0.02, green: 0.04, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: period == .month ? "moon.fill" : "globe.americas.fill")
                .font(.system(size: 150))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 40, y: 20)
                .accessibilityHidden(true)
        }
    }

    private func bar(_ f: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(8, g.size.width * f))
            }
        }
        .frame(height: 8)
    }

    private func ring(_ f: Double) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 8)
            Circle().trim(from: 0, to: f)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percent(f)).font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit()
        }
        .frame(width: 78, height: 78)
    }

    private func percent(_ f: Double) -> String { "\(Int((f * 100).rounded(.down)))%" }

    /// "Sep 1 → Sep 30" / "Jan 1 → Dec 31, 2026".
    private func rangeLabel(_ span: DateInterval) -> String {
        let last = span.end.addingTimeInterval(-1)
        let start = span.start.formatted(.dateTime.month(.abbreviated).day())
        let end = period == .month ? last.formatted(.dateTime.month(.abbreviated).day())
                                   : last.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) → \(end)"
    }

    /// "Day 14 of 30" / "Day 257 of 365".
    private func dayLabel(_ span: DateInterval, now: Date) -> String {
        let cal = Calendar.current
        let total = cal.dateComponents([.day], from: span.start, to: span.end).day ?? 0
        let today = (cal.dateComponents([.day], from: span.start, to: now).day ?? 0) + 1
        return "Day \(today) of \(total)"
    }

    static func interval(_ period: Period, containing date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: period == .month ? .month : .year, for: date)
            ?? DateInterval(start: date, duration: 1)
    }

    static func fraction(of span: DateInterval, at date: Date) -> Double {
        guard span.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(span.start) / span.duration, 0), 1)
    }
}
