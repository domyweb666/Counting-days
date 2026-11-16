import Foundation

/// 天氣用的縣市。使用者在設定裡選一個，存的是 `id`。
public struct WeatherCity: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// 縣市政府所在地的大概位置。查預報時送出去的就是這一組，每個選同一個縣市的人送的都一樣。
    public let latitude: Double
    public let longitude: Double

    /// 22 個縣市都在同一個時區，預報的「哪一天」照這個時區算
    public static let timeZoneID = "Asia/Taipei"

    /// 22 個縣市，北到南、東部、離島
    public static let all: [WeatherCity] = [
        WeatherCity(id: "keelung", name: "基隆市", latitude: 25.1283, longitude: 121.7419),
        WeatherCity(id: "taipei", name: "臺北市", latitude: 25.0375, longitude: 121.5637),
        WeatherCity(id: "newtaipei", name: "新北市", latitude: 25.0120, longitude: 121.4657),
        WeatherCity(id: "taoyuan", name: "桃園市", latitude: 24.9937, longitude: 121.3010),
        WeatherCity(id: "hsinchu-city", name: "新竹市", latitude: 24.8066, longitude: 120.9686),
        WeatherCity(id: "hsinchu-county", name: "新竹縣", latitude: 24.8270, longitude: 121.0128),
        WeatherCity(id: "miaoli", name: "苗栗縣", latitude: 24.5648, longitude: 120.8207),
        WeatherCity(id: "taichung", name: "臺中市", latitude: 24.1619, longitude: 120.6468),
        WeatherCity(id: "changhua", name: "彰化縣", latitude: 24.0756, longitude: 120.5445),
        WeatherCity(id: "nantou", name: "南投縣", latitude: 23.9027, longitude: 120.6906),
        WeatherCity(id: "yunlin", name: "雲林縣", latitude: 23.6992, longitude: 120.5262),
        WeatherCity(id: "chiayi-city", name: "嘉義市", latitude: 23.4812, longitude: 120.4536),
        WeatherCity(id: "chiayi-county", name: "嘉義縣", latitude: 23.4588, longitude: 120.2930),
        WeatherCity(id: "tainan", name: "臺南市", latitude: 22.9920, longitude: 120.1850),
        WeatherCity(id: "kaohsiung", name: "高雄市", latitude: 22.6210, longitude: 120.3118),
        WeatherCity(id: "pingtung", name: "屏東縣", latitude: 22.6830, longitude: 120.4879),
        WeatherCity(id: "yilan", name: "宜蘭縣", latitude: 24.7307, longitude: 121.7630),
        WeatherCity(id: "hualien", name: "花蓮縣", latitude: 23.9913, longitude: 121.6197),
        WeatherCity(id: "taitung", name: "臺東縣", latitude: 22.7554, longitude: 121.1503),
        WeatherCity(id: "penghu", name: "澎湖縣", latitude: 23.5700, longitude: 119.5665),
        WeatherCity(id: "kinmen", name: "金門縣", latitude: 24.4368, longitude: 118.3186),
        WeatherCity(id: "lienchiang", name: "連江縣", latitude: 26.1577, longitude: 119.9520)
    ]

    /// 存檔裡的識別碼不在清單上（沒選過，或資料壞了）就當成沒選
    public static func find(_ id: String?) -> WeatherCity? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// 一天的預報。只留畫面用得到的幾樣。
public struct DayForecast: Codable, Hashable, Sendable {
    /// 哪一天，寫成「2026-11-17」
    public var dayKey: String
    /// SF Symbols 的圖示名稱，Apple 天氣給的
    public var symbolName: String
    /// 「多雲」「陣雨」這種一兩個字的描述，Apple 天氣給的
    public var condition: String
    /// 最高、最低溫（攝氏，四捨五入到整數）
    public var high: Int
    public var low: Int
    /// 降雨機率，0 到 100
    public var rainPercent: Int

    public init(dayKey: String, symbolName: String, condition: String, high: Int, low: Int, rainPercent: Int) {
        self.dayKey = dayKey
        self.symbolName = symbolName
        self.condition = condition
        self.high = high
        self.low = low
        self.rainPercent = rainPercent
    }
}

/// Apple 規定顯示天氣的地方要有 Apple Weather 標誌，和一個連到資料來源說明的連結
public struct WeatherCredit: Codable, Hashable, Sendable {
    public var markLight: URL
    public var markDark: URL
    public var legalPage: URL

    public init(markLight: URL, markDark: URL, legalPage: URL) {
        self.markLight = markLight
        self.markDark = markDark
        self.legalPage = legalPage
    }
}

/// 存在手機裡的那一份預報
public struct WeatherCache: Codable, Equatable, Sendable {
    public var cityID: String
    public var fetchedAt: Date
    public var days: [DayForecast]
    public var credit: WeatherCredit

    public init(cityID: String, fetchedAt: Date, days: [DayForecast], credit: WeatherCredit) {
        self.cityID = cityID
        self.fetchedAt = fetchedAt
        self.days = days
        self.credit = credit
    }
}

public enum WeatherRules {
    /// 距離上次抓超過這麼久才再抓：3 小時
    public static let refreshAfter: TimeInterval = 3 * 3600
    /// 合理的攝氏溫度範圍，超出就當成資料壞了
    public static let temperatureRange = -60...60

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let month = c.month ?? 0, day = c.day ?? 0
        return "\(c.year ?? 0)-" + (month < 10 ? "0\(month)" : "\(month)") + "-" + (day < 10 ? "0\(day)" : "\(day)")
    }

    /// 外面進來的資料先檢查：圖示名稱是空的、溫度離譜、最低比最高還高、降雨機率不在 0 到 100，那一天就不要
    public static func isValid(_ forecast: DayForecast) -> Bool {
        !forecast.symbolName.isEmpty
            && temperatureRange.contains(forecast.high)
            && temperatureRange.contains(forecast.low)
            && forecast.low <= forecast.high
            && (0...100).contains(forecast.rainPercent)
    }

    /// 要不要去抓：沒有資料、換了縣市、或是放超過 3 小時。時鐘被往回調（上次抓的時間在未來）也重抓。
    public static func needsRefresh(_ cache: WeatherCache?, cityID: String, now: Date) -> Bool {
        guard let cache, cache.cityID == cityID else { return true }
        let age = now.timeIntervalSince(cache.fetchedAt)
        return age < 0 || age >= refreshAfter
    }

    /// 那一天的預報。縣市對不上、那天已經過了、或沒有那天的資料，都回傳 nil（畫面上就什麼都不顯示）。
    public static func forecast(
        in cache: WeatherCache?, cityID: String?, day: Date, today: Date, calendar: Calendar
    ) -> DayForecast? {
        guard let cache, let cityID, cache.cityID == cityID else { return nil }
        guard calendar.startOfDay(for: day) >= calendar.startOfDay(for: today) else { return nil }
        let key = dayKey(day, calendar: calendar)
        return cache.days.first { $0.dayKey == key }
    }

    /// 「22–28°」
    public static func temperatures(_ forecast: DayForecast) -> String {
        "\(forecast.low)–\(forecast.high)°"
    }

    /// 「多雲 · 22–28° · 降雨 40%」。沒有描述的時候只寫後兩樣。
    public static func line(_ forecast: DayForecast) -> String {
        var parts: [String] = []
        let condition = forecast.condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !condition.isEmpty { parts.append(condition) }
        parts.append(temperatures(forecast))
        parts.append("降雨 \(forecast.rainPercent)%")
        return parts.joined(separator: " · ")
    }

    /// 「今天 08:12」或「11月16日 08:12」
    public static func updatedText(_ fetchedAt: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: fetchedAt)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        let clock = (hour < 10 ? "0\(hour)" : "\(hour)") + ":" + (minute < 10 ? "0\(minute)" : "\(minute)")
        if calendar.isDate(fetchedAt, inSameDayAs: now) { return "今天 " + clock }
        return "\(c.month ?? 0)月\(c.day ?? 0)日 " + clock
    }
}
