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
    let weather: WeatherStore
    @ObservationIgnored private var controlObserver: NSObjectProtocol?

    init() {
        let store = EventStore()
        let settings = SettingsStore()
        self.store = store
        self.settings = settings
        self.purchase = PurchaseStore(onChange: { settings.setUnlocked($0) })
        self.vm = CalendarViewModel(store: store, settings: settings)
        self.weather = WeatherStore()
        // 評分時機要知道裝了幾天。舊版升上來的沒有這筆，從打開新版這天開始算
        if settings.value.firstOpenedAt == nil {
            settings.update { $0.firstOpenedAt = Date() }
        }
        #if DEBUG
        DemoSeeder.runIfAsked(store: store, settings: settings)
        #endif
        // 控制中心的「新增行程」（Widget/NewEventControl.swift）。在這裡收：從控制中心冷開機時，動作比畫面早跑，
        // 畫面還沒出來就先記著，月曆一出現再打開表單
        controlObserver = NotificationCenter.default.addObserver(
            forName: .newEventControlPressed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.vm.openNewEventFromControl() }
        }
    }

    /// 那一天要顯示的天氣。沒開天氣、沒選縣市、那天沒有預報（過去的日子、十天以後）都是 nil，畫面上就不顯示。
    func forecast(for day: Date) -> DayForecast? {
        let s = settings.value
        guard s.weatherEnabled else { return nil }
        return WeatherRules.forecast(
            in: weather.cache, cityID: s.weatherCityID, day: day, today: vm.today, calendar: vm.calendar
        )
    }

    /// 這幾天裡只要有一天顯示了天氣，就要放來源標示
    func weatherCredit(for days: [Date]) -> WeatherCredit? {
        guard days.contains(where: { forecast(for: $0) != nil }) else { return nil }
        return weather.cache?.credit
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
    /// 捲動位置：畫面最上面那一週
    var topWeekID: Date?
    /// 清單方式的小月曆顯示哪個月
    private(set) var listMonth: Date
    /// 小月曆上一次換月是往後（true）還是往前，換月時從哪一邊滑進來看這個
    private(set) var listMonthForward = true
    /// 每點開一天就加一，月曆收到就把那天的面板捲到看得見。跳到某一天不算，那裡有自己的捲動。
    private(set) var panelReveal = 0
    /// 要跳去的那一週已經是最上面那一週、只是被捲掉一截時加一。`topWeekID` 沒變就不會捲，要另外請月曆對齊。
    private(set) var topRealign = 0
    /// 每從小工具點進來一次就加一，月曆收到就把擋在前面的畫面收掉
    private(set) var widgetOpens = 0
    /// 按了控制中心的「新增行程」、月曆還沒打開表單。用旗子不用次數：冷開機時網址比月曆早到，月曆一出現要看得到
    private(set) var wantsNewEvent = false
    /// 時間軸從哪一天開始排（週檢視會再對齊到一週的開頭）
    private(set) var timelineAnchor: Date

    @ObservationIgnored private var lunarCache: [Date: String] = [:]
    /// 上一次向系統行事曆查到的行程，和當時查的條件。
    /// 改設定、切檢視都會重排月曆，但行程沒變，就不用再去問一次行事曆（行程多的人，那一次查詢最慢）。
    @ObservationIgnored private var fetched: (key: FetchKey, events: [CalEvent])?
    /// 每重排一次月曆就加一。時間軸看到它沒變，就沿用上次排好的格子，拖動時不用每一格畫面重排。
    private(set) var layoutRevision = 0

    /// 查詢條件：行事曆變動次數、查詢範圍、時區。四樣都一樣，查出來的行程就一樣。
    private struct FetchKey: Equatable {
        let changeToken: Int
        let from: Date
        let to: Date
        let timeZoneID: String
    }

    static let dowNames = ["日", "一", "二", "三", "四", "五", "六"]

    init(store: EventStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        let cal = Self.makeCalendar(settings.value)
        store.displayTimeZone = cal.timeZone
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
        s.displayCalendar(device: .current)
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
    var timelineDays: [Date] { timelineDays(page: 0) }

    /// 從現在這一段往前、往後數第幾段要排的那幾天（0 是現在這一段，-1 上一段，1 下一段）
    func timelineDays(page: Int) -> [Date] {
        guard let count = viewKind.dayCount else { return [] }
        let start = count == 7 ? builder.startOfWeek(timelineAnchor) : timelineAnchor
        return (0..<count).map { builder.addDays(start, page * count + $0) }
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

    /// 標題寫的那個月是不是今天所在的月。不是的話，標題旁邊多一顆回到今天的鈕。
    var isShowingThisMonth: Bool {
        Self.monthStart(titleDate, calendar) == Self.monthStart(today, calendar)
    }

    // MARK: 重新查詢

    func rebuild() {
        let cal = Self.makeCalendar(settings.value)
        // 換了時區：查詢前先告訴 store，快取裡照舊時區算的也要清掉
        if store.displayTimeZone.identifier != cal.timeZone.identifier {
            store.displayTimeZone = cal.timeZone
            ensureWindowAfterTimeZoneChange(cal)
        }
        let previousToday = builder.today
        builder = LayoutBuilder(calendar: cal, today: Date(), settings: settings.value)
        lunarCache.removeAll()
        guard store.hasAccess else {
            weeks = []
            upcoming = []
            countdowns = []
            layoutRevision += 1
            return
        }
        let events = windowEvents()
        weeks = builder.weeks(from: windowStart, to: builder.addDays(windowEnd, -1), events: events)
        upcoming = builder.upcoming(in: weeks)
        countdowns = makeCountdowns(windowEvents: events)
        layoutRevision += 1
        if previousToday != builder.today, selected == previousToday {
            selected = nil
        }
        // 週起始日改了之後，原本記的那一週可能不存在了
        if let top = topWeekID, !weeks.contains(where: { $0.id == top }) {
            topWeekID = builder.startOfWeek(top)
        }
    }

    /// 換時區之後，原本記的「今天」「被選的那天」「畫面最上面那一週」都是舊時區的午夜，對不上新的格子，全部回到今天重來。
    private func ensureWindowAfterTimeZoneChange(_ cal: Calendar) {
        let today = cal.startOfDay(for: Date())
        let month = Self.monthStart(today, cal)
        windowStart = Self.shift(month, months: -3, cal)
        windowEnd = Self.shift(month, months: 13, cal)
        listMonth = month
        timelineAnchor = today
        selected = nil
        let fresh = LayoutBuilder(calendar: cal, today: Date(), settings: settings.value)
        topWeekID = fresh.startOfWeek(today)
    }

    /// 預覽用的設定：使用者自己的類別，範例行事曆照順序分到這些類別
    private var previewSettings: AppSettings {
        let categories = settings.value.categories
        return AppSettings(categories: categories, calendarCategory: SampleEvents.calendarCategory(for: categories))
    }

    /// 主題頁的預覽：今天起七天、套上範例行程的一週。
    /// 只算出一份拿去畫，不碰 `weeks`、`selected`，外面的月曆不受影響。
    func themePreviewWeek() -> WeekModel? {
        // 今天排在最左邊。照日曆的那一週排的話，週末打開時範例行程幾乎都落在下一週。
        var previewCalendar = calendar
        previewCalendar.firstWeekday = previewCalendar.component(.weekday, from: today)
        let previewBuilder = LayoutBuilder(calendar: previewCalendar, today: today, settings: previewSettings)
        let lastDay = previewBuilder.addDays(today, 6)

        // 範例裡的「台南行」排在 11 天後，進不了這七天；預覽另外放一段在第 4 到 6 天，才看得到跨日色帶
        var events = SampleEvents.events(today: today, calendar: previewCalendar).filter { $0.id != "demo.tainan" }
        events.append(CalEvent(
            id: "preview.tainan",
            title: "台南行",
            start: previewBuilder.addDays(today, 3),
            end: previewBuilder.addDays(today, 6).addingTimeInterval(-1),
            isAllDay: true,
            calendarID: "demo.fun"
        ))
        return previewBuilder.weeks(from: today, to: lastDay, events: events).first
    }

    /// 月曆樣式頁「清單」預覽下面那幾張「接下來」的卡，從預覽那一週算
    func themePreviewUpcoming(in week: WeekModel, count: Int = 3) -> [UpcomingCard] {
        let previewBuilder = LayoutBuilder(calendar: calendar, today: today, settings: previewSettings)
        return Array(previewBuilder.upcoming(in: [week], limit: count).prefix(count))
    }

    /// 月曆載入範圍內的行程。查詢條件跟上一次一樣就沿用，不再問系統行事曆。
    private func windowEvents() -> [CalEvent] {
        let key = FetchKey(
            changeToken: store.changeToken,
            from: windowStart,
            to: windowEnd,
            timeZoneID: store.displayTimeZone.identifier
        )
        if let fetched, fetched.key == key { return fetched.events }
        let events = store.events(from: windowStart, to: windowEnd)
        fetched = (key, events)
        return events
    }

    /// 回到前景時用：在背景那段時間，別的 app 可能改過行事曆，下一次重排一定重新查。
    func forgetFetchedEvents() {
        fetched = nil
    }

    private func makeCountdowns(windowEvents: [CalEvent]) -> [CountdownItem] {
        let ids = settings.visibleCountdowns
        guard !ids.isEmpty,
              let end = calendar.date(byAdding: .year, value: 2, to: today) else { return [] }
        let hidden = settings.value.hiddenCalendarIDs
        // 先在月曆已經查到的行程裡找：範圍有蓋到今天時，在這裡找到的就是兩年內最近的那一次。
        // 找不到的（下一次在載入範圍之後），才另外查兩年。
        let windowCovers = windowStart <= today && today < windowEnd
        let inWindow = windowCovers
            ? windowEvents.filter { $0.end > today && $0.start < end && !hidden.contains($0.calendarID) }
            : []
        var later: [CalEvent]?
        var items: [CountdownItem] = []
        for id in ids {
            var found = inWindow.filter { $0.seriesID == id }.min { $0.start < $1.start }
            if found == nil {
                if later == nil {
                    later = store.events(from: today, to: end).filter { !hidden.contains($0.calendarID) }
                }
                found = later?.filter { $0.seriesID == id }.min { $0.start < $1.start }
            }
            guard let next = found else { continue }
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

    // MARK: 行事曆清單

    /// 有加入蒜日子的行事曆，照使用者排的順序；沒排過的照名稱接在後面
    var shownCalendars: [EKCalendar] {
        let removed = settings.value.hiddenCalendarIDs
        let shown = store.calendars.filter { !removed.contains($0.calendarIdentifier) }
        let byID = Dictionary(shown.map { ($0.calendarIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return CalendarOrder.sorted(shown.map(\.calendarIdentifier), by: settings.value.calendarOrder)
            .compactMap { byID[$0] }
    }

    /// 從蒜日子移除的行事曆。手機上還在，隨時可以加回來。
    var removedCalendars: [EKCalendar] {
        let removed = settings.value.hiddenCalendarIDs
        return store.calendars.filter { removed.contains($0.calendarIdentifier) }
    }

    // MARK: 選取與移動

    func day(for date: Date) -> DayModel? {
        for week in weeks {
            if let d = week.days.first(where: { $0.date == date }) { return d }
        }
        return nil
    }

    func toggle(_ date: Date) {
        let opens = selected != date
        withAnimation(Theme.Motion.change) {
            selected = opens ? date : nil
        }
        if opens { panelReveal += 1 }
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
        showListMonth(Self.monthStart(day, calendar))
        timelineAnchor = day
        let target = builder.startOfWeek(day)
        // 近的用捲的，看得出是往上還是往下。遠的直接跳：捲過一大段還沒排好高度的週，會停歪。
        if topWeekID == target {
            topRealign += 1
        } else if let from = topWeekID,
                  let days = calendar.dateComponents([.day], from: from, to: target).day,
                  abs(days) <= Self.animatedJumpDays {
            withAnimation(Theme.Motion.transition) { topWeekID = target }
        } else {
            topWeekID = target
        }
    }

    /// 離現在畫面最上面那一週幾天以內，跳過去時用捲的
    private static let animatedJumpDays = 56

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

    /// 從小工具點進來：停在今天
    func openFromWidget() {
        goToday()
        widgetOpens += 1
    }

    /// 從控制中心的「新增行程」或 suanrizi://new 進來：跟點小工具一樣停在今天、收掉擋在前面的，再由月曆打開新增
    func openNewEventFromControl() {
        openFromWidget()
        wantsNewEvent = true
    }

    /// 月曆處理完「新增行程」（打開了表單，或已經有一張開著）
    func newEventHandled() {
        wantsNewEvent = false
    }

    func shiftListMonth(_ months: Int) {
        let next = Self.shift(listMonth, months: months, calendar)
        ensureWindow(contains: next)
        showListMonth(next)
    }

    private func showListMonth(_ month: Date) {
        listMonthForward = month >= listMonth
        listMonth = month
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
