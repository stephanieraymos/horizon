import Foundation

/// One day's forecast for the trip weather strip.
struct DailyWeather: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let tempMax: Double
    let tempMin: Double
    let precipProbability: Int?
    let code: Int

    /// WMO weather-code → SF Symbol.
    var symbol: String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}

/// Persisted forecast cache stored on the trip row (`fam_trips.weather_cache`),
/// so the strip doesn't re-fetch on every view.
struct WeatherCache: Codable, Hashable {
    /// destination|startDate|endDate — invalidated when any of these change.
    var key: String
    var resolvedName: String
    var fetchedAt: Date
    var days: [Day]

    struct Day: Codable, Hashable {
        var date: Date
        var tempMax: Double
        var tempMin: Double
        var precip: Int?
        var code: Int
    }

    var daily: [DailyWeather] {
        days.map { DailyWeather(date: $0.date, tempMax: $0.tempMax, tempMin: $0.tempMin,
                                precipProbability: $0.precip, code: $0.code) }
    }

    init(key: String, resolvedName: String, fetchedAt: Date, from daily: [DailyWeather]) {
        self.key = key; self.resolvedName = resolvedName; self.fetchedAt = fetchedAt
        self.days = daily.map { .init(date: $0.date, tempMax: $0.tempMax, tempMin: $0.tempMin,
                                      precip: $0.precipProbability, code: $0.code) }
    }
}

/// Keyless weather via Open-Meteo (free, no API key, no Supabase egress).
/// Geocodes a destination name, then fetches the daily forecast for a date
/// range. Forecast only covers ~16 days ahead, so callers guard on that.
enum WeatherService {
    /// Max days ahead Open-Meteo's forecast covers.
    static let forecastWindowDays = 16

    struct GeoResult: Decodable { let latitude: Double; let longitude: Double; let name: String }

    static func geocode(_ query: String) async -> GeoResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json")
        else { return nil }
        struct Response: Decodable { let results: [GeoResult]? }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(Response.self, from: data).results?.first
        } catch { return nil }
    }

    static func dailyForecast(latitude: Double, longitude: Double,
                              start: Date, end: Date) async -> [DailyWeather] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        let startStr = f.string(from: start)
        let endStr = f.string(from: end)

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "daily", value: "weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "timezone", value: "auto"),
            .init(name: "start_date", value: startStr),
            .init(name: "end_date", value: endStr),
        ]
        guard let url = comps.url else { return [] }

        struct Daily: Decodable {
            let time: [String]
            let weathercode: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
        }
        struct Response: Decodable { let daily: Daily? }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let d = try JSONDecoder().decode(Response.self, from: data).daily else { return [] }
            return d.time.indices.compactMap { i in
                guard let date = f.date(from: d.time[i]),
                      i < d.weathercode.count,
                      i < d.temperature_2m_max.count,
                      i < d.temperature_2m_min.count else { return nil }
                return DailyWeather(
                    date: date,
                    tempMax: d.temperature_2m_max[i],
                    tempMin: d.temperature_2m_min[i],
                    precipProbability: d.precipitation_probability_max?[safe: i] ?? nil,
                    code: d.weathercode[i])
            }
        } catch { return [] }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
