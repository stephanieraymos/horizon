import SwiftUI

/// A forecast strip for the trip's destination around its dates. Uses keyless
/// Open-Meteo; the forecast only reaches ~16 days out, so further-off trips get
/// a friendly "check back closer" note instead.
struct TripWeatherSection: View {
    let trip: Trip
    let destinationName: String?

    @Environment(TripsStore.self) private var trips

    @State private var days: [DailyWeather] = []
    @State private var resolvedName: String?
    @State private var phase: Phase = .idle

    enum Phase { case idle, loading, tooFar, empty, loaded }

    private var destination: String? { destinationName?.nilIfBlank }
    private var departDate: Date? { trip.departDate }
    private var returnDate: Date? { trip.returnDate }

    /// How long a cached forecast is trusted before re-fetching.
    private let cacheTTL: TimeInterval = 6 * 3600

    var body: some View {
        if let destination, let depart = departDate {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Weather").font(.title3.bold())
                    Spacer()
                    if let resolvedName {
                        Text(resolvedName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .task(id: "\(destination)|\(depart.timeIntervalSince1970)|\(returnDate?.timeIntervalSince1970 ?? 0)") {
                await load(destination: destination, depart: depart)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            HStack { ProgressView(); Text("Checking the forecast…").font(.callout).foregroundStyle(.secondary) }
                .padding(.vertical, 4)
        case .tooFar:
            note("Forecast opens about \(WeatherService.forecastWindowDays) days before you leave. Check back closer!")
        case .empty:
            note("Couldn't load a forecast for this destination.")
        case .loaded:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days) { day in dayCard(day) }
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayCard(_ day: DailyWeather) -> some View {
        VStack(spacing: 6) {
            Text(day.date, format: .dateTime.weekday(.abbreviated)).font(.caption.weight(.semibold))
            Image(systemName: day.symbol).font(.title2).symbolRenderingMode(.multicolor)
                .frame(height: 26)
            Text("\(Int(day.tempMax.rounded()))°").font(.subheadline.weight(.bold))
            Text("\(Int(day.tempMin.rounded()))°").font(.caption).foregroundStyle(.secondary)
            if let pop = day.precipProbability, pop >= 20 {
                Label("\(pop)%", systemImage: "drop.fill")
                    .font(.caption2).foregroundStyle(.blue)
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(width: 66)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func load(destination: String, depart: Date) async {
        phase = .loading
        days = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let windowEnd = cal.date(byAdding: .day, value: WeatherService.forecastWindowDays, to: today) ?? today
        let departDay = cal.startOfDay(for: depart)

        guard departDay <= windowEnd else { phase = .tooFar; return }

        let start = max(today, departDay)
        let end = min(cal.startOfDay(for: returnDate ?? depart), windowEnd)
        let key = cacheKey(destination: destination, start: start, end: end)

        // Fresh cache for the same destination + range? Use it, no network.
        if let cache = trip.weatherCache, cache.key == key,
           Date().timeIntervalSince(cache.fetchedAt) < cacheTTL, !cache.days.isEmpty {
            resolvedName = cache.resolvedName
            days = cache.daily
            phase = .loaded
            return
        }

        guard let geo = await WeatherService.geocode(destination) else { phase = .empty; return }
        resolvedName = geo.name

        let result = await WeatherService.dailyForecast(latitude: geo.latitude, longitude: geo.longitude,
                                                        start: start, end: max(start, end))
        days = result
        phase = result.isEmpty ? .empty : .loaded

        if !result.isEmpty {
            let cache = WeatherCache(key: key, resolvedName: geo.name, fetchedAt: Date(), from: result)
            await trips.saveWeatherCache(tripID: trip.id, cache: cache)
        }
    }

    private func cacheKey(destination: String, start: Date, end: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return "\(destination.lowercased())|\(f.string(from: start))|\(f.string(from: end))"
    }
}
