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

/// 點小工具、控制中心按鈕時帶進蒜日子的網址。只認得「看今天」「新增行程」這兩個，多一個字都不算。
public enum WidgetLink {
    /// 前半段要跟 project.yml 的 CFBundleURLSchemes 一樣
    static let todayAddress = "suanrizi://today"
    static let newEventAddress = "suanrizi://new"

    public static var today: URL? { URL(string: todayAddress) }
    /// 控制中心的「新增行程」按鈕用
    public static var newEvent: URL? { URL(string: newEventAddress) }

    /// 從外面帶進來的網址是不是「看今天」。別的 app 也打得開這種網址，所以其他的一律不理。
    public static func opensToday(_ url: URL) -> Bool {
        url.absoluteString == todayAddress
    }

    /// 從外面帶進來的網址是不是「新增行程」。跟「看今天」一樣，不帶參數，其他的一律不理。
    public static func opensNewEvent(_ url: URL) -> Bool {
        url.absoluteString == newEventAddress
    }

    // MARK: 看某一天（中、大尺寸小工具上點某一格）

    static let dayPrefix = "suanrizi://day/"
    /// 帶進來的日期離今天最多幾天。小工具只畫這個月前後幾週，一年夠寬；再遠的不是小工具帶的，不理。
    static let dayReachDays = 366

    /// 小工具上某一格要帶的網址：suanrizi://day/2026-12-05。日期照蒜日子顯示用的行事曆（時區）算。
    public static func day(_ date: Date, calendar: Calendar) -> URL? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day, (1...9999).contains(y) else { return nil }
        let text = String(format: "%04d-%02d-%02d", y, m, d)
        return URL(string: dayPrefix + text)
    }

    /// 從外面帶進來的網址是不是「看某一天」，是的話回那一天的 0 點。
    /// 格式要一字不差（4 位年-2 位月-2 位日，不帶參數），日期要真的存在（2 月 30 日不算），而且離今天一年以內，其他一律回 nil。
    public static func openedDay(_ url: URL, calendar: Calendar, today: Date) -> Date? {
        let text = url.absoluteString
        guard text.hasPrefix(dayPrefix) else { return nil }
        let parts = text.dropFirst(dayPrefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { "0123456789".contains($0) } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        let wanted = DateComponents(year: y, month: m, day: d)
        guard let date = calendar.date(from: wanted) else { return nil }
        // calendar.date(from:) 會把 2 月 30 日推成 3 月 2 日，換回來對不上就是不存在的日子
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: day).day,
              abs(distance) <= dayReachDays
        else { return nil }
        return day
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

// MARK: - 第 66 片起的六種小工具

/// 蒜日子有哪幾種小工具。哪幾種要完整版看 `FullVersionAccess.canShowWidget`。
/// rawValue 接在 `com.domyweb.countingdays.widget.` 後面就是小工具的種類名，上架後不能改，
/// 改了使用者放在主畫面的那一塊會失效。
public enum WidgetStyle: String, CaseIterable, Sendable {
    /// 小尺寸「今天」（第 60 到 65 片）
    case today
    /// 小尺寸色塊小月曆
    case smallMonth = "month.small"
    /// 小尺寸倒數日
    case countdown
    /// 中尺寸彈性週：從今天起 7 天
    case flexWeek = "week.flex"
    /// 中尺寸小月曆加接下來
    case monthNext = "month.next"
    /// 大尺寸整月主事件
    case largeMonth = "month.large"
    /// 鎖定畫面長方形：今天下一件
    case lockNext = "lock.next"
}

/// 月曆格子上這一天要畫的那一件：上面有跨日的就是最上面那一條，沒有就是主事件。
/// 跟蒜日子清單樣式的小月曆（MiniCell）同一套：只看第 0 條跨日、再看主事件。
public struct WidgetMonthMark: Hashable, Sendable {
    public var label: String
    public var categoryID: String
}

/// 倒數日小工具要畫的那一個
public struct WidgetCountdown: Hashable, Sendable {
    public var title: String
    /// 那一天（已經開始的跨日行程算今天）
    public var date: Date
    /// 還有幾天，0 是今天
    public var days: Int
    /// 這一筆佔幾天，跨日的才大於 1
    public var totalDays: Int
    public var categoryID: String
}

extension WidgetRules {
    /// 倒數日往後查多遠（天）。跟蒜日子一樣看兩年內。
    public static let countdownDaysAhead = 731
    /// 「接下來」往後看幾天。小工具最多放三張，一個多月夠了。
    public static let upcomingDaysAhead = 42

    /// 這個月的格子：從這個月 1 號那一週排到月底那一週。每天的主事件、跨日都跟蒜日子的月曆同一份。
    public static func monthWeeks(events: [CalEvent], now: Date, calendar: Calendar, settings: AppSettings) -> [WeekModel] {
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        guard let month = calendar.dateInterval(of: .month, for: builder.today) else { return [] }
        let lastDay = builder.addDays(month.end, -1)
        return builder.weeks(from: month.start, to: lastDay, events: events)
    }

    /// 某一週第幾欄要畫的那一件。沒有就是 nil。
    public static func monthMark(in week: WeekModel, col: Int, settings: AppSettings) -> WidgetMonthMark? {
        guard week.days.indices.contains(col) else { return nil }
        if let seg = week.segments.first(where: { $0.band.lane == 0 && col >= $0.startCol && col <= $0.endCol }) {
            let event = seg.band.event
            return WidgetMonthMark(
                label: CellText.label(title: event.title, shortName: settings.shortNames[event.seriesID]),
                categoryID: seg.band.categoryID
            )
        }
        guard let head = week.days[col].head else { return nil }
        return WidgetMonthMark(label: head.label, categoryID: head.categoryID)
    }

    /// 從今天起 7 天排成一週，今天在最左邊（跟主題頁的預覽一樣，不照週日或週一起排）
    public static func weekFromToday(events: [CalEvent], now: Date, calendar: Calendar, settings: AppSettings) -> WeekModel? {
        var rolling = calendar
        rolling.firstWeekday = calendar.component(.weekday, from: now)
        let builder = LayoutBuilder(calendar: rolling, today: now, settings: settings)
        return builder.weeks(from: builder.today, to: builder.addDays(builder.today, 6), events: events).first
    }

    /// 「接下來」的前幾張，跟蒜日子清單樣式下面那一串同一份
    public static func upcoming(
        events: [CalEvent],
        now: Date,
        calendar: Calendar,
        settings: AppSettings,
        count: Int
    ) -> [UpcomingCard] {
        guard count > 0 else { return [] }
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        let weeks = builder.weeks(from: builder.today, to: builder.addDays(builder.today, upcomingDaysAhead), events: events)
        return Array(builder.upcoming(in: weeks, limit: count).prefix(count))
    }

    /// 日期下面那行小字：節日先，再來節氣或農曆（設定關掉農曆就只剩節日）。跟蒜日子月曆上的一樣。
    public static func subline(for day: DayModel, calendar: Calendar, settings: AppSettings) -> (text: String, isHoliday: Bool)? {
        if let holiday = day.holidays.first { return (String(holiday.prefix(3)), true) }
        guard settings.showLunar else { return nil }
        let text = Lunar.solarTerm(for: day.date, calendar: calendar)
            ?? Lunar.lunarDay(for: day.date.addingTimeInterval(12 * 3600), timeZone: calendar.timeZone).shortText
        return text.isEmpty ? nil : (text, false)
    }

    /// 最快到的那一個倒數日。規則跟蒜日子月曆上面那一排一樣：關掉的行事曆不算，已經開始的跨日行程算今天。
    /// `countdownIDs` 要先經過 `FullVersionAccess.visibleCountdowns`。
    public static func nextCountdown(
        events: [CalEvent],
        countdownIDs: [String],
        now: Date,
        calendar: Calendar,
        settings: AppSettings
    ) -> WidgetCountdown? {
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        var best: WidgetCountdown?
        for id in countdownIDs {
            let next = events
                .filter { $0.seriesID == id && !settings.hiddenCalendarIDs.contains($0.calendarID) }
                .filter { builder.lastDay(of: $0) >= builder.today }
                .min { $0.start < $1.start }
            guard let next else { continue }
            let first = calendar.startOfDay(for: next.start)
            let day = max(first, builder.today)
            let item = WidgetCountdown(
                title: next.title,
                date: day,
                days: builder.dayDistance(from: builder.today, to: day),
                totalDays: builder.isMultiDay(next) ? builder.dayDistance(from: first, to: builder.lastDay(of: next)) + 1 : 1,
                categoryID: Classifier.categoryID(for: next, settings: settings)
            )
            if let current = best, current.days <= item.days { continue }
            best = item
        }
        return best
    }
}
