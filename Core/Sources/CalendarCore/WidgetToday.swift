import Foundation

/// 蒜日子與小工具共用的抽屜（App Group）。蒜日子每次存設定多寫一份進去，小工具只讀。
/// 裡面只放設定，「買了沒」不准放。
public enum WidgetShared {
    /// 要跟 project.yml 兩支程式的權利宣告、Apple 開發者後台的 App Group 一樣
    public static let appGroupID = "group.com.domyweb.countingdays"
    /// 抽屜裡放設定的那一格，內容是 AppSettings 的 JSON
    public static let settingsKey = "settings.v1"

    /// 把抽屜裡那一格讀成設定。沒有東西表示蒜日子用的是預設值，跟著用預設值。
    /// 有東西但讀不回來就丟錯，不當成預設值：預設值沒有關掉任何行事曆，會把使用者藏起來的行程放到主畫面上。
    public static func settings(from data: Data?) throws -> AppSettings {
        guard let data else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }
}

/// 點小工具時帶進蒜日子的網址。只認得「看今天」這一個，多一個字都不算。
public enum WidgetLink {
    /// 前半段要跟 project.yml 的 CFBundleURLSchemes 一樣
    static let todayAddress = "suanrizi://today"

    public static var today: URL? { URL(string: todayAddress) }

    /// 從外面帶進來的網址是不是「看今天」。別的 app 也打得開這種網址，所以其他的一律不理。
    public static func opensToday(_ url: URL) -> Bool {
        url.absoluteString == todayAddress
    }
}

/// 小工具上的一列行程
public struct WidgetRow: Identifiable, Hashable, Sendable {
    /// 「全天」或開始時間（例："14:30"）
    public var timeText: String
    public var label: String
    public var categoryID: String
    public var event: CalEvent

    public var id: String { event.id }
}

/// 小工具「今天」要畫的內容
public struct WidgetToday: Hashable, Sendable {
    public var rows: [WidgetRow]
    /// 放不下、沒列出來的還有幾筆
    public var moreCount: Int
    /// 今天是什麼節日。不佔一列，寫在日期旁邊。
    public var holiday: String?

    public init(rows: [WidgetRow], moreCount: Int, holiday: String? = nil) {
        self.rows = rows
        self.moreCount = moreCount
        self.holiday = holiday
    }

    /// 只留前面幾列，其餘算進「還有幾筆」。小工具的高度不夠時用。
    public func limited(to count: Int) -> WidgetToday {
        let shown = min(max(0, count), rows.count)
        return WidgetToday(
            rows: Array(rows.prefix(shown)),
            moreCount: moreCount + rows.count - shown,
            holiday: holiday
        )
    }
}

/// 小工具上要放哪幾筆。哪些行程算今天的、誰排前面，都跟蒜日子裡點開今天看到的一樣（用同一個 LayoutBuilder），
/// 只多兩條：已經結束的不放、每天重複的例行事件不放。
/// 順序：跨日的、全天的、有時間的照開始時間。
public enum WidgetRules {
    /// 小尺寸最多列幾筆
    public static let smallRowLimit = 3
    /// 隔多久重新查一次行事曆（秒）。在別的 app 加的行程，最慢要等這麼久才會出現。
    /// iPhone 一天大約只給 40 到 70 次，一小時一次在額度內。
    public static let refreshInterval: TimeInterval = 3600

    public static func today(
        events: [CalEvent],
        now: Date,
        calendar: Calendar,
        settings: AppSettings,
        limit: Int = smallRowLimit
    ) -> WidgetToday {
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        let days = builder.weeks(from: builder.today, to: builder.today, events: events).flatMap(\.days)
        guard let day = days.first(where: { $0.isToday }) else { return WidgetToday(rows: [], moreCount: 0) }

        var rows: [WidgetRow] = []
        for band in day.bands.sorted(by: { $0.lane < $1.lane }) {
            rows.append(WidgetRow(
                timeText: "全天",
                label: CellText.label(title: band.event.title, shortName: settings.shortNames[band.event.seriesID]),
                categoryID: band.categoryID,
                event: band.event
            ))
        }
        // 全天的整天都在；有時間的，結束時間一到就拿掉
        for e in day.events where e.event.isAllDay || max(e.event.start, e.event.end) > now {
            rows.append(WidgetRow(
                timeText: builder.timeText(e.event),
                label: e.label,
                categoryID: e.categoryID,
                event: e.event
            ))
        }

        let shown = max(0, limit)
        return WidgetToday(
            rows: Array(rows.prefix(shown)),
            moreCount: max(0, rows.count - shown),
            holiday: day.holidays.first
        )
    }

    /// 從現在到明天結束，哪些時刻要換畫面：每一筆行程結束的時候、過午夜的時候。第一個是現在。
    /// 連明天一起排，系統晚一點才來重新查也不會停在昨天。
    public static func moments(events: [CalEvent], now: Date, calendar: Calendar, settings: AppSettings) -> [Date] {
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        let tomorrow = builder.addDays(builder.today, 1)
        let limit = builder.addDays(builder.today, 2)
        let ends = builder.weeks(from: builder.today, to: tomorrow, events: events)
            .flatMap(\.days)
            .filter { $0.date == builder.today || $0.date == tomorrow }
            .flatMap(\.events)
            .filter { !$0.event.isAllDay }
            .map { max($0.event.start, $0.event.end) }
        let later = Set(ends + [tomorrow]).filter { $0 > now && $0 < limit }
        return [now] + later.sorted()
    }
}
