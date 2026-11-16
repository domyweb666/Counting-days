import CoreLocation
import Foundation
import Observation
import WeatherKit
import CalendarCore

/// 天氣：向 Apple 天氣查使用者選的縣市未來十天的預報，存一份在手機裡。
/// 蒜日子只有這裡會連網，而且只在設定裡開了天氣、選了縣市之後。送出去的只有那個縣市的固定座標。
/// 要不要抓、哪一天顯示什麼，都問 Core 的 `WeatherRules`。
@MainActor
@Observable
final class WeatherStore {
    /// 手機裡的那一份預報。沒抓過是 nil。
    private(set) var cache: WeatherCache?
    /// 最近一次抓不到的原因，給設定頁顯示。抓成功就清掉。
    private(set) var problem: String?
    private(set) var isLoading = false

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "weatherCache.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            cache = try JSONDecoder().decode(WeatherCache.self, from: data)
        } catch {
            // 存的那一份讀不出來就當成沒有，下次會重新抓
            problem = "手機裡存的天氣讀不出來，會重新抓一次。"
        }
    }

    /// 開了天氣、選了縣市，而且手機裡的資料沒有或太舊，才去抓
    func refreshIfNeeded(settings: AppSettings) {
        guard settings.weatherEnabled, let city = WeatherCity.find(settings.weatherCityID) else { return }
        guard !isLoading, WeatherRules.needsRefresh(cache, cityID: city.id, now: Date()) else { return }
        Task { await refresh(city: city) }
    }

    /// 向 Apple 天氣查這個縣市的預報。失敗的話舊資料留著，原因寫進 `problem`。
    func refresh(city: WeatherCity) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let place = CLLocation(latitude: city.latitude, longitude: city.longitude)
        do {
            // 來源標示是 Apple 規定要顯示的，拿不到就不能顯示天氣，所以跟預報一起要
            let attribution = try await WeatherService.shared.attribution
            let daily = try await WeatherService.shared.weather(for: place, including: .daily)
            let days = daily.forecast.map { Self.convert($0) }.filter { WeatherRules.isValid($0) }
            guard !days.isEmpty else {
                problem = "Apple 天氣回來的資料不對，先用上次的。"
                return
            }
            let fresh = WeatherCache(
                cityID: city.id,
                fetchedAt: Date(),
                days: days,
                credit: WeatherCredit(
                    markLight: attribution.combinedMarkLightURL,
                    markDark: attribution.combinedMarkDarkURL,
                    legalPage: attribution.legalPageURL
                )
            )
            cache = fresh
            problem = nil
            defaults.set(try JSONEncoder().encode(fresh), forKey: Self.key)
        } catch {
            problem = "目前抓不到天氣：\(error.localizedDescription)"
        }
    }

    private static func convert(_ day: DayWeather) -> DayForecast {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: WeatherCity.timeZoneID) ?? calendar.timeZone
        return DayForecast(
            dayKey: WeatherRules.dayKey(day.date, calendar: calendar),
            symbolName: day.symbolName,
            condition: day.condition.description,
            high: Int(day.highTemperature.converted(to: .celsius).value.rounded()),
            low: Int(day.lowTemperature.converted(to: .celsius).value.rounded()),
            rainPercent: Int((day.precipitationChance * 100).rounded())
        )
    }
}
