import EventKit
import Foundation
import Observation
import CalendarCore

/// 系統行事曆是唯一的資料來源。這裡只負責讀寫 EventKit，不另外存一份。
@MainActor
@Observable
final class EventStore {
    let ek = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// 系統行事曆每變動一次就加一，畫面看到它變了就重新查詢
    private(set) var changeToken = 0
    var lastError: String?

    @ObservationIgnored private var cache: [String: EKEvent] = [:]
    /// 月曆照哪個時區排。跟手機不一樣時，全天行程的起訖要搬到這個時區的同一個鐘面時間。
    /// 由 `CalendarViewModel` 每次重新查詢前告知。
    @ObservationIgnored var displayTimeZone: TimeZone = .current
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: ek, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.bump() }
        }
    }

    var hasAccess: Bool { status == .fullAccess }

    private func bump() {
        cache.removeAll()
        changeToken += 1
    }

    func refreshStatus() {
        let now = EKEventStore.authorizationStatus(for: .event)
        if now != status {
            status = now
            bump()
        }
    }

    func requestAccess() async {
        do {
            _ = try await ek.requestFullAccessToEvents()
        } catch {
            lastError = "要求行事曆權限時出錯：\(error.localizedDescription)"
        }
        status = EKEventStore.authorizationStatus(for: .event)
        bump()
    }

    // MARK: 讀

    var calendars: [EKCalendar] {
        // 讀一下變動次數：行事曆有增減時，列出行事曆的畫面才會跟著重畫
        _ = changeToken
        guard hasAccess else { return [] }
        return ek.calendars(for: .event).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func events(from start: Date, to end: Date) -> [CalEvent] {
        guard hasAccess, end > start else { return [] }
        let predicate = ek.predicateForEvents(withStart: start, end: end, calendars: nil)
        return ek.events(matching: predicate).compactMap { convert($0) }
    }

    private func convert(_ e: EKEvent) -> CalEvent? {
        // 外面進來的資料先檢查：缺識別碼或日期的事件不顯示
        guard let seriesID = e.eventIdentifier,
              let start = e.startDate,
              let end = e.endDate,
              let calendar = e.calendar else { return nil }
        let id = seriesID + "|" + String(start.timeIntervalSinceReferenceDate)
        cache[id] = e
        let rules = e.recurrenceRules ?? []
        let title = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 識別碼用原本的開始時間算，下面搬過的時間只拿來排月曆
        let device = TimeZone.current
        let floats = e.isAllDay && displayTimeZone.identifier != device.identifier
        return CalEvent(
            id: id,
            seriesID: seriesID,
            title: title.isEmpty ? "（沒有標題）" : title,
            start: floats ? FloatingTime.moved(start, from: device, to: displayTimeZone) : start,
            end: floats ? FloatingTime.moved(end, from: device, to: displayTimeZone) : end,
            isAllDay: e.isAllDay,
            calendarID: calendar.calendarIdentifier,
            location: e.location,
            hasAttendees: e.hasAttendees,
            isRecurring: e.hasRecurrenceRules,
            isDailyRoutine: rules.contains { $0.frequency == .daily && $0.interval == 1 }
        )
    }

    /// 找回 EventKit 的原始事件，交給系統的編輯畫面
    func ekEvent(for event: CalEvent) -> EKEvent? {
        if let hit = cache[event.id] { return hit }
        // 快取裡沒有（系統行事曆剛通知有變動、月曆還沒重新查完）：照月曆當初查到它的方法，用日期範圍再查一次。
        // 只靠識別碼去找不夠：有些帳號的行程用識別碼找不回來，重複的行程找回來的也是第一次那一筆。
        let day: TimeInterval = 24 * 60 * 60
        let predicate = ek.predicateForEvents(
            withStart: event.start.addingTimeInterval(-day),
            end: max(event.end, event.start).addingTimeInterval(day),
            calendars: nil
        )
        let same = ek.events(matching: predicate).filter { $0.eventIdentifier == event.seriesID }
        let exact = same.first {
            guard let start = $0.startDate else { return false }
            return event.seriesID + "|" + String(start.timeIntervalSinceReferenceDate) == event.id
        }
        return exact ?? same.first ?? ek.event(withIdentifier: event.seriesID)
    }

    func title(forSeries id: String) -> String? {
        guard hasAccess else { return nil }
        return ek.event(withIdentifier: id)?.title
    }

    // MARK: 寫

    /// 建立一本新的行事曆，寫進 iPhone。成功回傳 nil，失敗回傳要給使用者看的原因。
    /// 蒜日子自己寫進系統行事曆的有四件事：這裡的建立行事曆，和下面的新增、修改、刪除行程。
    /// 表單改不了的行程（唯讀的行事曆、結束比開始早的怪資料）照舊交給系統的編輯畫面。
    func createCalendar(title: String, color: CGColor) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasAccess else { return "蒜日子沒有行事曆權限，沒辦法建立。" }
        guard !name.isEmpty else { return "先幫行事曆取個名字。" }
        guard let source = sourceForNewCalendar() else {
            return "這支手機上找不到可以放新行事曆的帳號。請到 iPhone 的行事曆 app 建立。"
        }
        let calendar = EKCalendar(for: .event, eventStore: ek)
        calendar.title = name
        calendar.cgColor = color
        calendar.source = source
        do {
            try ek.saveCalendar(calendar, commit: true)
        } catch {
            return "沒有建立成功：\(error.localizedDescription)"
        }
        bump()
        return nil
    }

    /// 新增一筆行程，寫進系統行事曆（規格第 20 節）。`time` 是照月曆的時區算好的起訖。
    /// 成功回傳存好的那一筆，失敗回傳要給使用者看的原因，兩個剛好有一個。
    func addEvent(_ draft: NewEventDraft, time: ResolvedEventTime) -> (event: EKEvent?, problem: String?) {
        let name = draft.cleanTitle
        guard hasAccess else { return (nil, "蒜日子沒有行事曆權限，沒辦法儲存。") }
        guard !name.isEmpty else { return (nil, "先幫行程取個標題。") }
        guard let id = draft.calendarID, let target = ek.calendar(withIdentifier: id) else {
            return (nil, "找不到要存進去的行事曆，請重新選一本。")
        }
        guard target.allowsContentModifications else {
            return (nil, "「\(target.title)」這本行事曆不能寫入，請換一本。")
        }
        guard time.end >= time.start else { return (nil, "結束時間比開始時間早，請重新選時間。") }

        let event = EKEvent(eventStore: ek)
        event.title = name
        event.calendar = target
        event.isAllDay = time.isAllDay
        // 全天行程沒有時區，系統照手機時區的午夜記。月曆照別的時區排時，把鐘面時間搬回手機的時區。
        let device = TimeZone.current
        let floats = time.isAllDay && displayTimeZone.identifier != device.identifier
        event.startDate = floats ? FloatingTime.moved(time.start, from: displayTimeZone, to: device) : time.start
        event.endDate = floats ? FloatingTime.moved(time.end, from: displayTimeZone, to: device) : time.end
        if let reminder = draft.reminder {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(reminder.offsetSeconds)))
        }
        if let repeats = draft.repeats {
            event.addRecurrenceRule(recurrenceRule(repeats))
        }
        let place = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { event.location = place }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { event.notes = notes }
        do {
            try ek.save(event, span: .thisEvent, commit: true)
        } catch {
            return (nil, "沒有存成功：\(error.localizedDescription)")
        }
        bump()
        return (event, nil)
    }

    // MARK: 修改、刪除既有的行程

    /// 編輯既有行程時，表單一開始要帶入的東西
    struct EditSeed {
        let event: EKEvent
        let draft: NewEventDraft
        /// 原本的提醒、重複規則表單表示不了（例如 15 分鐘前、每個月第二個週三）。使用者沒去動就照原本的留著。
        let keepsOtherReminder: Bool
        let keepsOtherRepeat: Bool
    }

    /// 這一筆能用蒜日子自己的畫面改就回傳要帶入的東西；找不到、唯讀、或起訖顛倒就回傳 nil，改開系統的編輯畫面。
    func editSeed(for event: CalEvent, ownCategoryID: String?, calendar: Calendar) -> EditSeed? {
        guard hasAccess, NewEventRules.canEditHere(event), let found = ekEvent(for: event),
              let home = found.calendar, home.allowsContentModifications else { return nil }
        var draft = NewEventRules.draft(editing: event, calendar: calendar)
        // 讀出來的標題沒有的話會補成「（沒有標題）」，表單要拿原本的
        draft.title = found.title ?? ""
        draft.notes = found.notes ?? ""
        draft.reminder = reminder(of: found)
        draft.repeats = repeats(of: found)
        draft.categoryID = ownCategoryID
        return EditSeed(
            event: found,
            draft: draft,
            keepsOtherReminder: draft.reminder == nil && !(found.alarms ?? []).isEmpty,
            keepsOtherRepeat: draft.repeats == nil && found.hasRecurrenceRules
        )
    }

    /// 原本只有一個提醒、而且對得上表單的選項，才回傳那一種
    private func reminder(of event: EKEvent) -> EventReminder? {
        guard let alarms = event.alarms, alarms.count == 1, let alarm = alarms.first,
              alarm.absoluteDate == nil else { return nil }
        return EventReminder.matching(offsetSeconds: Int(alarm.relativeOffset.rounded()), isAllDay: event.isAllDay)
    }

    /// 原本只有一條重複規則、沒有結束日、也沒有指定第幾個星期幾這類條件，才回傳表單上的那一種
    private func repeats(of event: EKEvent) -> EventRepeat? {
        guard let rules = event.recurrenceRules, rules.count == 1, let rule = rules.first,
              rule.recurrenceEnd == nil,
              (rule.daysOfTheWeek ?? []).count <= 1,
              (rule.daysOfTheMonth ?? []).count <= 1,
              (rule.monthsOfTheYear ?? []).count <= 1,
              (rule.setPositions ?? []).isEmpty else { return nil }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return .weekly
        case (.weekly, 2): return .biweekly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return nil
        }
    }

    /// 把表單上改過的欄位寫回那一筆行程。只寫有改的欄位：表單上沒有的東西（邀請對象、網址、
    /// 表示不了的提醒與重複規則）才不會被洗掉。成功回傳 nil，失敗回傳要給使用者看的原因。
    /// `allFuture`：重複的行程要不要連之後的一起改。
    func updateEvent(
        _ event: EKEvent,
        from original: NewEventDraft,
        to draft: NewEventDraft,
        time: ResolvedEventTime,
        allFuture: Bool
    ) -> String? {
        let name = draft.cleanTitle
        guard hasAccess else { return "蒜日子沒有行事曆權限，沒辦法儲存。" }
        guard !name.isEmpty else { return "先幫行程取個標題。" }
        guard time.end >= time.start else { return "結束時間比開始時間早，請重新選時間。" }
        if draft.calendarID != original.calendarID {
            guard let id = draft.calendarID, let target = ek.calendar(withIdentifier: id) else {
                return "找不到要存進去的行事曆，請重新選一本。"
            }
            guard target.allowsContentModifications else {
                return "「\(target.title)」這本行事曆不能寫入，請換一本。"
            }
            event.calendar = target
        }
        if name != original.cleanTitle { event.title = name }
        if !NewEventRules.hasSameTime(original, draft) {
            event.isAllDay = time.isAllDay
            let device = TimeZone.current
            let floats = time.isAllDay && displayTimeZone.identifier != device.identifier
            event.startDate = floats ? FloatingTime.moved(time.start, from: displayTimeZone, to: device) : time.start
            event.endDate = floats ? FloatingTime.moved(time.end, from: displayTimeZone, to: device) : time.end
        }
        if draft.reminder != original.reminder {
            for alarm in event.alarms ?? [] { event.removeAlarm(alarm) }
            if let reminder = draft.reminder {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(reminder.offsetSeconds)))
            }
        }
        if draft.repeats != original.repeats {
            for rule in event.recurrenceRules ?? [] { event.removeRecurrenceRule(rule) }
            if let repeats = draft.repeats {
                event.addRecurrenceRule(recurrenceRule(repeats))
            }
        }
        let place = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if place != original.location.trimmingCharacters(in: .whitespacesAndNewlines) {
            event.location = place.isEmpty ? nil : place
        }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes != original.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
            event.notes = notes.isEmpty ? nil : notes
        }
        do {
            try ek.save(event, span: allFuture ? .futureEvents : .thisEvent, commit: true)
        } catch {
            // 沒存成功就把那一筆還原，不然畫面上拿到的會是改到一半的樣子
            event.rollback()
            return "沒有存成功：\(error.localizedDescription)"
        }
        bump()
        return nil
    }

    /// 刪掉一筆行程。成功回傳 nil，失敗回傳要給使用者看的原因。
    func deleteEvent(_ event: EKEvent, allFuture: Bool) -> String? {
        guard hasAccess else { return "蒜日子沒有行事曆權限，沒辦法刪除。" }
        do {
            try ek.remove(event, span: allFuture ? .futureEvents : .thisEvent, commit: true)
        } catch {
            return "沒有刪掉：\(error.localizedDescription)"
        }
        bump()
        return nil
    }

    private func recurrenceRule(_ repeats: EventRepeat) -> EKRecurrenceRule {
        switch repeats {
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    /// iPhone「設定」裡指定的預設行事曆
    var defaultCalendarID: String? {
        guard hasAccess else { return nil }
        return ek.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// 新行事曆放哪個帳號：先找 iCloud，沒有就放在這支手機上，再沒有才用新行程預設的那個帳號。
    /// Google 這類帳號通常不讓 iPhone 替它建立行事曆，所以不優先用。
    private func sourceForNewCalendar() -> EKSource? {
        let sources = ek.sources
        return sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? sources.first { $0.sourceType == .local }
            ?? ek.defaultCalendarForNewEvents?.source
    }

    /// 用標題或地點找事件：往前一年、往後兩年
    func search(_ text: String, today: Date, calendar: Calendar, hidden: Set<String>) -> [CalEvent] {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              let from = calendar.date(byAdding: .year, value: -1, to: today),
              let to = calendar.date(byAdding: .year, value: 2, to: today) else { return [] }
        let hits = events(from: from, to: to).filter {
            !hidden.contains($0.calendarID) && ($0.title.localizedCaseInsensitiveContains(key)
                || ($0.location ?? "").localizedCaseInsensitiveContains(key))
        }
        let future = hits.filter { $0.end >= today }.sorted { $0.start < $1.start }
        let past = hits.filter { $0.end < today }.sorted { $0.start > $1.start }
        return Array((future + past).prefix(200))
    }
}
