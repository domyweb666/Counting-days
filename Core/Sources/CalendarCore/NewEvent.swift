import Foundation

// 自己的新增行程畫面（規格第 20 節）用到的規則：帶入什麼、起訖怎麼推、月曆點兩下、畫面與分享的文字、行事曆檔。
// 都不靠 iPhone，才能單獨測。

/// 提醒。有時間的行程用前六種，全天行程用後兩種（全天沒有「開始前幾分鐘」可言）。
public enum EventReminder: String, CaseIterable, Sendable {
    case atStart
    case minutes5
    case minutes10
    case minutes30
    case hour1
    case day1
    case sameDayMorning
    case dayBeforeMorning

    /// 全天行程提醒的鐘點：早上 9 點
    public static let allDayHour = 9

    public static let timedCases: [EventReminder] = [.atStart, .minutes5, .minutes10, .minutes30, .hour1, .day1]
    public static let allDayCases: [EventReminder] = [.sameDayMorning, .dayBeforeMorning]

    public var isForAllDay: Bool { EventReminder.allDayCases.contains(self) }

    /// 既有行程上的提醒對得上表單的哪一種。對不上（例如 15 分鐘前）回傳 nil，那個提醒就照原本的留著。
    public static func matching(offsetSeconds: Int, isAllDay: Bool) -> EventReminder? {
        (isAllDay ? allDayCases : timedCases).first { $0.offsetSeconds == offsetSeconds }
    }

    /// 相對於行程開始的秒數，負的是之前。全天行程的開始是那天的午夜。
    public var offsetSeconds: Int {
        switch self {
        case .atStart: return 0
        case .minutes5: return -5 * 60
        case .minutes10: return -10 * 60
        case .minutes30: return -30 * 60
        case .hour1: return -3600
        case .day1: return -86400
        case .sameDayMorning: return EventReminder.allDayHour * 3600
        case .dayBeforeMorning: return EventReminder.allDayHour * 3600 - 86400
        }
    }

    /// 選單上的字
    public var label: String {
        switch self {
        case .atStart: return "準時"
        case .minutes5: return "5 分鐘前"
        case .minutes10: return "10 分鐘前"
        case .minutes30: return "30 分鐘前"
        case .hour1: return "1 小時前"
        case .day1: return "1 天前"
        case .sameDayMorning: return "當天早上 9 點"
        case .dayBeforeMorning: return "前一天早上 9 點"
        }
    }

    /// 設了之後寫在表單上的那一句
    public var summary: String {
        switch self {
        case .atStart: return "準時提醒"
        default: return label + "提醒"
        }
    }
}

public enum EventRepeat: String, CaseIterable, Sendable {
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    public var label: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每週"
        case .biweekly: return "每兩週"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    /// 從哪一天開始重複，寫成「每週二」「每月 17 日」這種
    public func summary(from day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: day)
        let weekday = "週" + EventText.weekdayName(day, calendar: calendar)
        switch self {
        case .daily: return "每天"
        case .weekly: return "每" + weekday
        case .biweekly: return "每兩週的" + weekday
        case .monthly: return "每月 \(c.day ?? 0) 日"
        case .yearly: return "每年 \(c.month ?? 0)月\(c.day ?? 0)日"
        }
    }
}

/// 表單上正在填的那一筆
public struct NewEventDraft: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 有起訖時間
        case timed
        /// 一天的全天行程
        case allDay
        /// 全天的跨日行程，用月曆點兩下選
        case multiDay
    }

    public var title: String
    public var kind: Kind
    /// 哪一天（那天的午夜）。有時間的行程與單日全天行程用。
    public var day: Date
    /// 開始時間：從午夜算起的分鐘數，0 到 1439
    public var startMinutes: Int
    /// 長度（分鐘）。跨好幾天的有時間行程會超過 1440；表單上把結束調到開始之前時是負的，那時候不能存。
    public var durationMinutes: Int
    /// 多天行程的起訖日（各自那天的午夜）。還沒點是 nil。
    public var rangeStart: Date?
    public var rangeEnd: Date?
    public var calendarID: String?
    public var reminder: EventReminder?
    public var repeats: EventRepeat?
    public var location: String
    public var notes: String
    /// 存好之後要不要出現分享那一頁
    public var wantsShare: Bool
    /// 使用者替這一筆選的類別。nil 是沒選，照行事曆的預設類別。
    public var categoryID: String?

    public init(
        title: String = "",
        kind: Kind = .timed,
        day: Date,
        startMinutes: Int,
        durationMinutes: Int = NewEventRules.defaultDuration,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        calendarID: String? = nil,
        reminder: EventReminder? = nil,
        repeats: EventRepeat? = nil,
        location: String = "",
        notes: String = "",
        wantsShare: Bool = false,
        categoryID: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.day = day
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.calendarID = calendarID
        self.reminder = reminder
        self.repeats = repeats
        self.location = location
        self.notes = notes
        self.wantsShare = wantsShare
        self.categoryID = categoryID
    }

    public var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 結束時間：從午夜算起的分鐘數。跨過午夜的話是隔天的鐘點。
    public var endMinutes: Int { (startMinutes + durationMinutes) % NewEventRules.minutesPerDay }

    /// 結束在隔天
    public var endsNextDay: Bool { startMinutes + durationMinutes >= NewEventRules.minutesPerDay }
}

/// 算好、可以寫進系統行事曆的起訖
public struct ResolvedEventTime: Equatable, Sendable {
    public var start: Date
    /// 有時間的行程是結束的那一刻；全天行程是最後一天的午夜
    public var end: Date
    public var isAllDay: Bool

    public init(start: Date, end: Date, isAllDay: Bool) {
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

public enum NewEventRules {
    public static let minutesPerDay = 1440
    public static let defaultDuration = 60
    /// 「多久」那排的三種長度
    public static let quickDurations = [30, 60, 120]
    /// 不是今天時帶入的開始時間：早上 9 點
    public static let defaultMorning = 9 * 60
    /// 「哪一天」那排直接點得到的天數：今天、明天、後天
    public static let quickDayCount = 3
    /// 滾輪上分鐘一格跳多少
    public static let minuteStep = 5

    /// 打開時帶入的開始時間：今天是下一個整點（最晚 23:00），其他天是早上 9 點
    public static func defaultStartMinutes(day: Date, now: Date, calendar: Calendar) -> Int {
        guard calendar.isDate(day, inSameDayAs: now) else { return defaultMorning }
        let hour = calendar.component(.hour, from: now)
        return min(hour + 1, 23) * 60
    }

    public static func initialDraft(day: Date, now: Date, calendar: Calendar) -> NewEventDraft {
        let start = calendar.startOfDay(for: day)
        return NewEventDraft(day: start, startMinutes: defaultStartMinutes(day: start, now: now, calendar: calendar))
    }

    /// 這一筆既有的行程能不能用蒜日子自己的畫面改。
    /// 表單的開始、結束各有日期與時間，跨好幾天的有時間行程也表示得了；只有結束比開始早的怪資料交給 iPhone 內建的畫面。
    public static func canEditHere(_ event: CalEvent) -> Bool {
        if event.isAllDay { return true }
        return event.end >= event.start
    }

    /// 把一筆既有的行程變成表單上的樣子。提醒、重複、備註、類別這裡不知道，由呼叫的人補。
    public static func draft(editing event: CalEvent, calendar: Calendar) -> NewEventDraft {
        let firstDay = calendar.startOfDay(for: event.start)
        var draft = NewEventDraft(
            title: event.title,
            day: firstDay,
            startMinutes: defaultMorning,
            calendarID: event.calendarID,
            location: event.location ?? ""
        )
        guard event.isAllDay else {
            let parts = calendar.dateComponents([.hour, .minute], from: event.start)
            draft.kind = .timed
            draft.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let minutes = Int((event.end.timeIntervalSince(event.start) / 60).rounded())
            draft.durationMinutes = max(minutes, 0)
            return draft
        }
        // 全天行程的結束，有的來源給最後一天的 23:59:59，有的給隔天的午夜。退一秒再取那天，兩種都落在最後一天。
        let lastMoment = event.end > event.start ? event.end.addingTimeInterval(-1) : event.end
        let lastDay = calendar.startOfDay(for: lastMoment)
        if lastDay > firstDay {
            draft.kind = .multiDay
            draft.rangeStart = firstDay
            draft.rangeEnd = lastDay
        } else {
            draft.kind = .allDay
        }
        return draft
    }

    /// 兩份表單的日期時間是不是一樣。編輯時一樣就不重寫起訖，原本的秒數、時區都不會被動到。
    public static func hasSameTime(_ a: NewEventDraft, _ b: NewEventDraft) -> Bool {
        a.kind == b.kind && a.day == b.day && a.startMinutes == b.startMinutes
            && a.durationMinutes == b.durationMinutes && a.rangeStart == b.rangeStart && a.rangeEnd == b.rangeEnd
    }

    /// 表單上那一排類別要標哪一顆：自己選過就是那一個；沒選就是存下去之後會歸到的那一類
    /// （標題對到關鍵字規則就照規則，不然照行事曆的預設類別）。
    public static func shownCategoryID(_ draft: NewEventDraft, settings: AppSettings) -> String {
        if let own = draft.categoryID, settings.categories.contains(where: { $0.id == own }) {
            return own
        }
        let preview = CalEvent(
            id: "", title: draft.cleanTitle, start: draft.day, end: draft.day, calendarID: draft.calendarID ?? ""
        )
        return Classifier.categoryID(for: preview, settings: settings)
    }

    /// 那一天是今天起算的第幾天。0、1、2 對應「今天」「明天」「後天」，其他回傳 nil。
    public static func quickDayIndex(of day: Date, today: Date, calendar: Calendar) -> Int? {
        let from = calendar.startOfDay(for: today)
        let to = calendar.startOfDay(for: day)
        guard let diff = calendar.dateComponents([.day], from: from, to: to).day,
              diff >= 0, diff < quickDayCount else { return nil }
        return diff
    }

    /// 調開始時間：長度不變，結束跟著移
    public static func settingStart(_ minutes: Int, in draft: NewEventDraft) -> NewEventDraft {
        var next = draft
        next.startMinutes = clampMinutes(minutes)
        return next
    }

    /// 調結束時間：長度跟著變。比開始早（或一樣）就當成隔天。
    public static func settingEnd(_ minutes: Int, in draft: NewEventDraft) -> NewEventDraft {
        var next = draft
        let gap = clampMinutes(minutes) - draft.startMinutes
        next.durationMinutes = gap > 0 ? gap : gap + minutesPerDay
        return next
    }

    private static func clampMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), minutesPerDay - 1)
    }

    /// 多天行程在月曆上點一天。
    /// 還沒有開始日：這天當開始。有開始沒結束：點在開始之前就改當開始，否則當結束。兩個都有了：重新選，這天當開始。
    public static func tappingRangeDay(_ day: Date, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        var next = draft
        let tapped = calendar.startOfDay(for: day)
        guard let start = draft.rangeStart, draft.rangeEnd == nil else {
            next.rangeStart = tapped
            next.rangeEnd = nil
            return next
        }
        if tapped < start {
            next.rangeStart = tapped
        } else {
            next.rangeEnd = tapped
        }
        return next
    }

    /// 多天行程一共幾天。還沒點開始日是 0，只點了一天是 1。
    public static func rangeDayCount(_ draft: NewEventDraft, calendar: Calendar) -> Int {
        guard let start = draft.rangeStart else { return 0 }
        guard let end = draft.rangeEnd else { return 1 }
        let diff = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(diff, 0) + 1
    }

    /// 算出要寫進行事曆的起訖。多天行程還沒點任何一天時回傳 nil。
    public static func resolve(_ draft: NewEventDraft, calendar: Calendar) -> ResolvedEventTime? {
        switch draft.kind {
        case .timed:
            let day = calendar.startOfDay(for: draft.day)
            guard let start = calendar.date(
                bySettingHour: draft.startMinutes / 60, minute: draft.startMinutes % 60, second: 0, of: day
            ) else { return nil }
            let end = start.addingTimeInterval(TimeInterval(draft.durationMinutes * 60))
            return ResolvedEventTime(start: start, end: end, isAllDay: false)
        case .allDay:
            let day = calendar.startOfDay(for: draft.day)
            return ResolvedEventTime(start: day, end: day, isAllDay: true)
        case .multiDay:
            guard let start = draft.rangeStart else { return nil }
            return ResolvedEventTime(start: start, end: draft.rangeEnd ?? start, isAllDay: true)
        }
    }

    /// 換成全天或換回有時間時，原本選的提醒如果不適用就拿掉
    public static func reminder(_ reminder: EventReminder?, fitting kind: NewEventDraft.Kind) -> EventReminder? {
        guard let reminder else { return nil }
        let wantsAllDay = kind != .timed
        return reminder.isForAllDay == wantsAllDay ? reminder : nil
    }

    /// 預設存到哪一本：上次用的那本還在就用它，不然用 iPhone 設定的預設行事曆，再不然用清單第一本。
    /// `available` 是有加入蒜日子、而且寫得進去的行事曆，照顯示順序。
    public static func pickCalendar(lastUsed: String?, systemDefault: String?, available: [String]) -> String? {
        if let lastUsed, available.contains(lastUsed) { return lastUsed }
        if let systemDefault, available.contains(systemDefault) { return systemDefault }
        return available.first
    }

    /// 月曆一個月的格子：前面補空格對齊星期，之後是那個月的每一天
    public static func monthCells(month: Date, calendar: Calendar) -> [Date?] {
        let parts = calendar.dateComponents([.year, .month], from: month)
        guard let first = calendar.date(from: parts),
              let days = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<days.count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        return cells
    }
}

// MARK: 開始、結束各有日期與時間
//
// 表單上是「開始：日期、時間」「結束：日期、時間」加一顆「整日」。存的還是上面那一份草稿：
// 有時間的行程存開始那天、開始的鐘點、長度；整日的存一天，或起訖兩天。這裡負責兩邊互換。
extension NewEventRules {
    /// 調時間時下面那一排直接點得到的長度
    public static let durationChoices = [30, 60, 120, 180]

    public static func isAllDay(_ draft: NewEventDraft) -> Bool { draft.kind != .timed }

    /// 開始那一天（那天的午夜）
    public static func startDay(_ draft: NewEventDraft) -> Date {
        draft.kind == .multiDay ? (draft.rangeStart ?? draft.day) : draft.day
    }

    /// 結束那一天（那天的午夜）
    public static func endDay(_ draft: NewEventDraft, calendar: Calendar) -> Date {
        switch draft.kind {
        case .timed:
            return calendar.startOfDay(for: timedEnd(draft, calendar: calendar) ?? draft.day)
        case .allDay:
            return draft.day
        case .multiDay:
            return draft.rangeEnd ?? draft.rangeStart ?? draft.day
        }
    }

    /// 結束的鐘點：從午夜算起的分鐘數。整日的行程沒有鐘點，回傳 0。
    public static func endClock(_ draft: NewEventDraft, calendar: Calendar) -> Int {
        guard draft.kind == .timed, let end = timedEnd(draft, calendar: calendar) else { return 0 }
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 起訖有沒有顛倒。顛倒的時候畫面上把結束劃掉，不能存。
    public static func hasValidTime(_ draft: NewEventDraft) -> Bool {
        switch draft.kind {
        case .timed:
            return draft.durationMinutes >= 0
        case .allDay:
            return true
        case .multiDay:
            guard let start = draft.rangeStart else { return false }
            return (draft.rangeEnd ?? start) >= start
        }
    }

    /// 改開始的日期：長度不變，結束跟著移
    public static func settingStartDay(_ day: Date, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        let picked = calendar.startOfDay(for: day)
        guard draft.kind != .timed else {
            var next = draft
            next.day = picked
            return next
        }
        let span = days(from: startDay(draft), to: endDay(draft, calendar: calendar), calendar: calendar)
        let end = calendar.date(byAdding: .day, value: span, to: picked) ?? picked
        return allDay(draft, from: picked, to: end)
    }

    /// 改結束的日期：開始不動。比開始那天早的不收。
    public static func settingEndDay(_ day: Date, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        let picked = calendar.startOfDay(for: day)
        let start = startDay(draft)
        guard picked >= start else { return draft }
        guard draft.kind == .timed else { return allDay(draft, from: start, to: picked) }
        return settingEnd(day: picked, clock: endClock(draft, calendar: calendar), in: draft, calendar: calendar)
    }

    /// 改結束的鐘點：開始不動，日期不動。調到開始之前就是顛倒，由 `hasValidTime` 擋下來。
    public static func settingEndClock(_ minutes: Int, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        guard draft.kind == .timed else { return draft }
        return settingEnd(day: endDay(draft, calendar: calendar), clock: minutes, in: draft, calendar: calendar)
    }

    /// 直接點一種長度：結束改成開始之後那麼久
    public static func settingDuration(_ minutes: Int, in draft: NewEventDraft) -> NewEventDraft {
        guard draft.kind == .timed else { return draft }
        var next = draft
        next.durationMinutes = max(minutes, 0)
        return next
    }

    /// 開或關「整日」。日期照舊；關掉時鐘點用回原本的。提醒不適用的話拿掉。
    public static func settingAllDay(_ on: Bool, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        if on {
            guard draft.kind == .timed else { return draft }
            let end = max(endDay(draft, calendar: calendar), draft.day)
            var next = allDay(draft, from: draft.day, to: end)
            next.reminder = reminder(draft.reminder, fitting: next.kind)
            return next
        }
        guard draft.kind != .timed else { return draft }
        let start = startDay(draft)
        let span = days(from: start, to: endDay(draft, calendar: calendar), calendar: calendar)
        // 同一天之內的長度：原本存的還在就用它，不然用預設的一小時
        let within = ((draft.durationMinutes % minutesPerDay) + minutesPerDay) % minutesPerDay
        var next = draft
        next.kind = .timed
        next.day = start
        next.rangeStart = nil
        next.rangeEnd = nil
        next.durationMinutes = span * minutesPerDay + (within == 0 ? defaultDuration : within)
        next.reminder = reminder(draft.reminder, fitting: .timed)
        return next
    }

    // MARK: 內部

    private static func moment(_ day: Date, clock: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: calendar.startOfDay(for: day))
    }

    /// 有時間的行程結束的那一刻
    private static func timedEnd(_ draft: NewEventDraft, calendar: Calendar) -> Date? {
        moment(draft.day, clock: draft.startMinutes, calendar: calendar)?
            .addingTimeInterval(TimeInterval(draft.durationMinutes * 60))
    }

    private static func settingEnd(day: Date, clock: Int, in draft: NewEventDraft, calendar: Calendar) -> NewEventDraft {
        let safe = min(max(clock, 0), minutesPerDay - 1)
        guard let from = moment(draft.day, clock: draft.startMinutes, calendar: calendar),
              let to = moment(day, clock: safe, calendar: calendar) else { return draft }
        var next = draft
        next.durationMinutes = Int((to.timeIntervalSince(from) / 60).rounded())
        return next
    }

    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        max(calendar.dateComponents([.day], from: from, to: to).day ?? 0, 0)
    }

    /// 整日的行程：起訖同一天就是單日，不同天就是多天
    private static func allDay(_ draft: NewEventDraft, from start: Date, to end: Date) -> NewEventDraft {
        var next = draft
        next.day = start
        if end > start {
            next.kind = .multiDay
            next.rangeStart = start
            next.rangeEnd = end
        } else {
            next.kind = .allDay
            next.rangeStart = nil
            next.rangeEnd = nil
        }
        return next
    }
}

/// 畫面上與分享出去的日期時間文字
public enum EventText {
    static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    public static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        weekdayNames[(calendar.component(.weekday, from: date) - 1 + 7) % 7]
    }

    /// 「11月16日 週一」
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)月\(c.day ?? 0)日 週\(weekdayName(date, calendar: calendar))"
    }

    /// 「11/26 週四」
    public static func shortDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0) 週\(weekdayName(date, calendar: calendar))"
    }

    /// 「2026年12月」
    public static func month(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    public static func isAfternoon(_ minutes: Int) -> Bool { minutes >= 12 * 60 }

    /// 12 小時制的鐘點：0 點和 12 點都寫成 12
    public static func hour12(_ minutes: Int) -> Int {
        let hour = (minutes / 60) % 12
        return hour == 0 ? 12 : hour
    }

    /// 「4:00」
    public static func clock(_ minutes: Int) -> String {
        let minute = minutes % 60
        return "\(hour12(minutes)):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// 24 小時制的鐘點，沒有上午下午：「9:05」「17:00」
    public static func clock24(_ minutes: Int) -> String {
        let day = NewEventRules.minutesPerDay
        let safe = ((minutes % day) + day) % day
        let minute = safe % 60
        return "\(safe / 60):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// 「下午 4:00」
    public static func time(_ minutes: Int) -> String {
        (isAfternoon(minutes) ? "下午 " : "上午 ") + clock(minutes)
    }

    /// 起訖時間。同是上午或同是下午只寫一次：「下午 4:00 – 5:00」；跨過午夜：「下午 11:00 – 隔天上午 1:00」
    public static func timeRange(startMinutes: Int, durationMinutes: Int) -> String {
        let total = startMinutes + durationMinutes
        let end = total % NewEventRules.minutesPerDay
        if total >= NewEventRules.minutesPerDay {
            return time(startMinutes) + " – 隔天" + time(end)
        }
        if isAfternoon(startMinutes) == isAfternoon(end) {
            return time(startMinutes) + " – " + clock(end)
        }
        return time(startMinutes) + " – " + time(end)
    }

    /// 長度寫成字：「30 分」「1 小時」「1 小時 30 分」
    public static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) 分" }
        if rest == 0 { return "\(hours) 小時" }
        return "\(hours) 小時 \(rest) 分"
    }

    /// 表單上、分享出去的那一行日期時間
    public static func when(_ draft: NewEventDraft, calendar: Calendar) -> String {
        switch draft.kind {
        case .timed:
            // 跨好幾天的有時間行程：兩頭都寫出日期與時間
            if draft.durationMinutes >= NewEventRules.minutesPerDay {
                let endDay = NewEventRules.endDay(draft, calendar: calendar)
                return day(draft.day, calendar: calendar) + " " + time(draft.startMinutes) + " 到 "
                    + day(endDay, calendar: calendar) + " " + time(NewEventRules.endClock(draft, calendar: calendar))
            }
            return day(draft.day, calendar: calendar) + " "
                + timeRange(startMinutes: draft.startMinutes, durationMinutes: draft.durationMinutes)
        case .allDay:
            return day(draft.day, calendar: calendar) + "（整日）"
        case .multiDay:
            guard let start = draft.rangeStart else { return "" }
            guard let end = draft.rangeEnd, end != start else {
                return day(start, calendar: calendar) + "（整日）"
            }
            return day(start, calendar: calendar) + " 到 " + day(end, calendar: calendar) + "（整日）"
        }
    }

    /// 分享給別人的那段文字：標題、日期時間，有地點多一行
    public static func shareText(_ draft: NewEventDraft, calendar: Calendar) -> String {
        var lines = [draft.cleanTitle, when(draft, calendar: calendar)]
        let place = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { lines.append(place) }
        return lines.joined(separator: "\n")
    }
}

/// 分享用的行事曆檔（iCalendar，RFC 5545）。對方點了可以加進自己的行事曆。
/// 提醒不放進去。有時間的行程用世界協調時間寫，所以重複行程在有日光節約的地方，換季後會差一小時。
public enum ICSFile {
    static let lineLimit = 75

    public static func make(
        uid: String,
        draft: NewEventDraft,
        time: ResolvedEventTime,
        stamp: Date,
        calendar: Calendar
    ) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//DOMYWEB//SuanRiZi//ZH",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:" + escape(uid),
            "DTSTAMP:" + utc(stamp),
            "SUMMARY:" + escape(draft.cleanTitle)
        ]
        if time.isAllDay {
            // 全天行程的結束日是「最後一天的隔天」
            let after = calendar.date(byAdding: .day, value: 1, to: time.end) ?? time.end
            lines.append("DTSTART;VALUE=DATE:" + dateOnly(time.start, calendar: calendar))
            lines.append("DTEND;VALUE=DATE:" + dateOnly(after, calendar: calendar))
        } else {
            lines.append("DTSTART:" + utc(time.start))
            lines.append("DTEND:" + utc(time.end))
        }
        if let rule = draft.repeats {
            lines.append("RRULE:" + recurrence(rule))
        }
        let place = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { lines.append("LOCATION:" + escape(place)) }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("DESCRIPTION:" + escape(notes)) }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// 檔名：標題裡不能當檔名的字換成底線，空的就叫「行程」
    public static func fileName(title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.map { banned.contains($0) ? "_" : String($0) }.joined()
        let name = String(clean.prefix(40))
        return (name.isEmpty ? "行程" : name) + ".ics"
    }

    static func recurrence(_ rule: EventRepeat) -> String {
        switch rule {
        case .daily: return "FREQ=DAILY"
        case .weekly: return "FREQ=WEEKLY"
        case .biweekly: return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly: return "FREQ=MONTHLY"
        case .yearly: return "FREQ=YEARLY"
        }
    }

    /// 文字裡的反斜線、分號、逗號、換行要跳脫
    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case ";": out += "\\;"
            case ",": out += "\\,"
            case "\n", "\r\n": out += "\\n"
            case "\r": break
            default: out.append(ch)
            }
        }
        return out
    }

    /// 一行最多 75 個位元組，超過要折行，下一行開頭多一個空白。不能把一個字切成兩半。
    static func fold(_ line: String) -> String {
        var parts: [String] = []
        var current = ""
        var size = 0
        for ch in line {
            let bytes = String(ch).utf8.count
            // 接續行開頭的那個空白也算一個位元組
            let limit = parts.isEmpty ? lineLimit : lineLimit - 1
            if size + bytes > limit {
                parts.append(current)
                current = ""
                size = 0
            }
            current.append(ch)
            size += bytes
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
    }

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func four(_ n: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, 4 - s.count)) + s
    }

    static func utc(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? cal.timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return four(c.year ?? 0) + two(c.month ?? 0) + two(c.day ?? 0)
            + "T" + two(c.hour ?? 0) + two(c.minute ?? 0) + two(c.second ?? 0) + "Z"
    }

    static func dateOnly(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return four(c.year ?? 0) + two(c.month ?? 0) + two(c.day ?? 0)
    }
}
