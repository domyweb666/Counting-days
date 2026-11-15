import EventKit
import Foundation
import Observation
import SwiftUI
import CalendarCore

struct CountdownItem: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let days: Int
    let categoryID: String

    var text: String {
        if days == 0 { return "今天" }
        if days == 1 { return "明天" }
        return "還有 \(days) 天"
    }
}

struct Subline: Hashable {
    let text: String
    let isHoliday: Bool
}

@MainActor
@Observable
final class AppModel {
    let store: EventStore
    let settings: SettingsStore
    let vm: CalendarViewModel
    let purchase: PurchaseStore

    init() {
        let store = EventStore()
        let settings = SettingsStore()
        self.store = store
        self.settings = settings
        self.purchase = PurchaseStore(onChange: { settings.setUnlocked($0) })
        self.vm = CalendarViewModel(store: store, settings: settings)
    }
}

@MainActor
@Observable
final class CalendarViewModel {
    let store: EventStore
    let settings: SettingsStore

    private(set) var weeks: [WeekModel] = []
    private(set) var upcoming: [UpcomingCard] = []
    private(set) var countdowns: [CountdownItem] = []
    private(set) var builder: LayoutBuilder
    /// 目前載入的範圍：[windowStart, windowEnd)
    private(set) var windowStart: Date
    private(set) var windowEnd: Date

    var selected: Date?
    /// 新手引導期間改吃這份範例行程，不讀系統行事曆。平常是 nil。
    var demoEvents: [CalEvent]?
    /// 捲動位置：畫面最上面那一週
    var topWeekID: Date?
    /// 清單方式的小月曆顯示哪個月
    private(set) var listMonth: Date
    /// 時間軸從哪一天開始排（週檢視會再對齊到一週的開頭）
    private(set) var timelineAnchor: Date

    @ObservationIgnored private var lunarCache: [Date: String] = [:]

    static let dowNames = ["日", "一", "二", "三", "四", "五", "六"]

    init(store: EventStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        let cal = Self.makeCalendar(settings.value)
        let b = LayoutBuilder(calendar: cal, today: Date(), settings: settings.value)
        builder = b
        let month = Self.monthStart(b.today, cal)
        windowStart = Self.shift(month, months: -3, cal)
        windowEnd = Self.shift(month, months: 13, cal)
        listMonth = month
        timelineAnchor = b.today
        topWeekID = b.startOfWeek(b.today)
    }

    // MARK: 日期工具

    static func makeCalendar(_ s: AppSettings) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "zh_Hant_TW")
        c.firstWeekday = s.weekStartsOnMonday ? 2 : 1
        return c
    }

    static func monthStart(_ date: Date, _ cal: Calendar) -> Date {
        let c = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: c) ?? cal.startOfDay(for: date)
    }

    static func shift(_ date: Date, months: Int, _ cal: Calendar) -> Date {
        cal.date(byAdding: .month, value: months, to: date) ?? date
    }

    var calendar: Calendar { builder.calendar }
    var today: Date { builder.today }

    var weekdaySymbols: [String] {
        let first = calendar.firstWeekday - 1
        return (0..<7).map { Self.dowNames[(first + $0) % 7] }
    }

    func dow(_ date: Date) -> String {
        Self.dowNames[calendar.component(.weekday, from: date) - 1]
    }

    func md(_ date: Date) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    func dayNumber(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    /// 格子上的日期：每月 1 號寫成「12/1」，其餘只寫日
    func cellLabel(_ date: Date) -> String {
        let d = dayNumber(date)
        return d == 1 ? md(date) : String(d)
    }

    /// 標題顯示的月份
    var titleDate: Date {
        switch viewKind {
        case .agenda:
            return today
        case .week, .threeDay, .day:
            let days = timelineDays
            return days.isEmpty ? today : days[days.count / 2]
        case .month:
            if settings.effectiveMode == .list { return listMonth }
            let top = topWeekID ?? builder.startOfWeek(today)
            return builder.addDays(top, 10)
        }
    }

    var viewKind: ViewKind { settings.value.view }

    /// 時間軸現在排的那幾天
    var timelineDays: [Date] {
        guard let count = viewKind.dayCount else { return [] }
        let start = count == 7 ? builder.startOfWeek(timelineAnchor) : timelineAnchor
        return (0..<count).map { builder.addDays(start, $0) }
    }

    /// 新增行程時預設帶入哪一天
    var focusDate: Date {
        if let selected, viewKind == .month { return selected }
        let days = timelineDays
        if days.isEmpty || days.contains(today) { return today }
        return days[0]
    }

    var titleMonthText: String { "\(calendar.component(.month, from: titleDate))月" }
    var titleYearText: String { String(calendar.component(.year, from: titleDate)) }

    // MARK: 重新查詢

    func rebuild() {
        let cal = Self.makeCalendar(settings.value)
        let previousToday = builder.today
        builder = LayoutBuilder(calendar: cal, today: Date(), settings: settings.value)
        lunarCache.removeAll()
        guard store.hasAccess else {
            weeks = []
            upcoming = []
            countdowns = []
            return
        }
        let events = demoEvents ?? store.events(from: windowStart, to: windowEnd)
        weeks = builder.weeks(from: windowStart, to: builder.addDays(windowEnd, -1), events: events)
        upcoming = builder.upcoming(in: weeks)
        countdowns = demoEvents == nil ? makeCountdowns() : []
        if previousToday != builder.today, selected == previousToday {
            selected = nil
        }
        // 週起始日改了之後，原本記的那一週可能不存在了
        if let top = topWeekID, !weeks.contains(where: { $0.id == top }) {
            topWeekID = builder.startOfWeek(top)
        }
    }

    /// 主題頁的預覽：今天起七天、套上範例行程的一週。
    /// 只算出一份拿去畫，不碰 `weeks`、`demoEvents`、`selected`，外面的月曆不受影響。
    func themePreviewWeek() -> WeekModel? {
        // 今天排在最左邊。照日曆的那一週排的話，週末打開時範例行程幾乎都落在下一週。
        var previewCalendar = calendar
        previewCalendar.firstWeekday = previewCalendar.component(.weekday, from: today)
        let sampleSettings = AppSettings(calendarCategory: CoachDemo.calendarCategory)
        let previewBuilder = LayoutBuilder(calendar: previewCalendar, today: today, settings: sampleSettings)
        let lastDay = previewBuilder.addDays(today, 6)

        // 引導的範例裡「台南行」排在 11 天後，進不了這七天；預覽另外放一段在第 4 到 6 天，才看得到跨日色帶
        var events = CoachDemo.events(today: today, calendar: previewCalendar).filter { $0.id != "demo.tainan" }
        events.append(CalEvent(
            id: "preview.tainan",
            title: "台南行",
            start: previewBuilder.addDays(today, 3),
            end: previewBuilder.addDays(today, 6).addingTimeInterval(-1),
            isAllDay: true,
            calendarID: "demo.trip"
        ))
        return previewBuilder.weeks(from: today, to: lastDay, events: events).first
    }

    private func makeCountdowns() -> [CountdownItem] {
        let ids = settings.visibleCountdowns
        guard !ids.isEmpty,
              let end = calendar.date(byAdding: .year, value: 2, to: today) else { return [] }
        let hidden = settings.value.hiddenCalendarIDs
        let events = store.events(from: today, to: end).filter { !hidden.contains($0.calendarID) }
        var items: [CountdownItem] = []
        for id in ids {
            let next = events.filter { $0.seriesID == id }.min { $0.start < $1.start }
            guard let next else { continue }
            let day = max(calendar.startOfDay(for: next.start), today)
            items.append(CountdownItem(
                id: id,
                title: next.title,
                date: day,
                days: builder.dayDistance(from: today, to: day),
                categoryID: Classifier.categoryID(for: next, settings: settings.value)
            ))
        }
        return items.sorted { $0.days < $1.days }
    }

    /// 第一次拿到權限時，把名稱像節日的行事曆自動設成節日層。
    /// 只看名稱不看類型：從 Google 帳號同步進來的節日行事曆不算「訂閱」，以前會漏掉。
    func autoDetectHolidaysIfNeeded() {
        guard store.hasAccess, !settings.value.didAutoDetectHolidays else { return }
        let ids = store.calendars
            .filter { cal in
                let t = cal.title
                return t.contains("節日") || t.contains("假日") || t.localizedCaseInsensitiveContains("holiday")
            }
            .map(\.calendarIdentifier)
        settings.update {
            $0.holidayCalendarIDs.formUnion(ids)
            $0.didAutoDetectHolidays = true
        }
    }

    // MARK: 選取與移動

    func day(for date: Date) -> DayModel? {
        for week in weeks {
            if let d = week.days.first(where: { $0.date == date }) { return d }
        }
        return nil
    }

    func toggle(_ date: Date) {
        withAnimation(.snappy(duration: 0.2)) {
            selected = selected == date ? nil : date
        }
    }

    private func ensureWindow(contains date: Date) {
        guard date < windowStart || date >= windowEnd else { return }
        let month = Self.monthStart(date, calendar)
        windowStart = Self.shift(month, months: -3, calendar)
        windowEnd = Self.shift(month, months: 13, calendar)
        rebuild()
    }

    func jump(to date: Date, select: Bool = true) {
        let day = calendar.startOfDay(for: date)
        ensureWindow(contains: day)
        if select { selected = day }
        listMonth = Self.monthStart(day, calendar)
        timelineAnchor = day
        topWeekID = builder.startOfWeek(day)
    }

    /// 時間軸往前、往後翻一段（一段就是目前排的天數）
    func shiftTimeline(_ pages: Int) {
        guard let count = viewKind.dayCount else { return }
        let next = builder.addDays(timelineAnchor, pages * count)
        ensureWindow(contains: next)
        timelineAnchor = next
    }

    /// 切到「天」檢視看某一天
    func openDay(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        ensureWindow(contains: day)
        timelineAnchor = day
        settings.update { $0.view = .day }
    }

    /// 從搜尋結果或倒數日點過來：月曆與時間軸直接跳到那一天；時間表改開那一天的「天」檢視
    func show(_ date: Date) {
        if viewKind == .agenda {
            openDay(date)
        } else {
            jump(to: date)
        }
    }

    func goToday() {
        rebuild()
        jump(to: today)
    }

    func shiftListMonth(_ months: Int) {
        let next = Self.shift(listMonth, months: months, calendar)
        ensureWindow(contains: next)
        listMonth = next
    }

    func loadEarlier() {
        let keep = weeks.first?.id
        windowStart = Self.shift(windowStart, months: -6, calendar)
        rebuild()
        topWeekID = keep
    }

    func loadLater() {
        windowEnd = Self.shift(windowEnd, months: 6, calendar)
        rebuild()
    }

    /// 清單方式的小月曆要畫的那幾週
    var listWeeks: [WeekModel] {
        let next = Self.shift(listMonth, months: 1, calendar)
        return weeks.filter { week in
            guard let last = week.days.last else { return false }
            return last.date >= listMonth && week.id < next
        }
    }

    func isInListMonth(_ date: Date) -> Bool {
        date >= listMonth && date < Self.shift(listMonth, months: 1, calendar)
    }

    // MARK: 顯示用

    /// 類別色塊的底色
    func color(_ categoryID: String) -> Color {
        Theme.category(hex: settings.value.category(id: categoryID).colorHex).fill
    }

    /// 壓在類別色塊上的字色
    func onColor(_ categoryID: String) -> Color {
        Theme.category(hex: settings.value.category(id: categoryID).colorHex).on
    }

    private func lunarText(_ date: Date) -> String {
        if let hit = lunarCache[date] { return hit }
        let text = Lunar.solarTerm(for: date, calendar: calendar)
            ?? Lunar.lunarDay(for: date.addingTimeInterval(12 * 3600), timeZone: calendar.timeZone).shortText
        lunarCache[date] = text
        return text
    }

    /// 日期數字下面那一行小字：節日優先，其次節氣與農曆
    func subline(for day: DayModel) -> Subline? {
        if let h = day.holidays.first {
            return Subline(text: String(h.prefix(3)), isHoliday: true)
        }
        guard settings.value.showLunar else { return nil }
        let text = lunarText(day.date)
        return text.isEmpty ? nil : Subline(text: text, isHoliday: false)
    }

    func lunarFullText(_ date: Date) -> String {
        let lunar = Lunar.lunarDay(for: date.addingTimeInterval(12 * 3600), timeZone: calendar.timeZone).fullText
        if let term = Lunar.solarTerm(for: date, calendar: calendar) { return lunar + " · " + term }
        return lunar
    }

    func accessibilityLabel(for day: DayModel) -> String {
        var parts = ["\(md(day.date)) 週\(dow(day.date))"]
        if day.isToday { parts.append("今天") }
        if let h = day.holidays.first { parts.append(h) }
        parts.append(day.count == 0 ? "沒有行程" : "\(day.count) 件")
        if let head = day.head { parts.append("主事件 \(head.event.title)") }
        for band in day.bands { parts.append(band.event.title) }
        return parts.joined(separator: "，")
    }
}
