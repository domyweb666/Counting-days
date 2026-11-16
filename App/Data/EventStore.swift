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
        return CalEvent(
            id: id,
            seriesID: seriesID,
            title: title.isEmpty ? "（沒有標題）" : title,
            start: start,
            end: end,
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
        return ek.event(withIdentifier: event.seriesID)
    }

    func title(forSeries id: String) -> String? {
        guard hasAccess else { return nil }
        return ek.event(withIdentifier: id)?.title
    }

    // MARK: 寫

    /// 建立一本新的行事曆，寫進 iPhone。成功回傳 nil，失敗回傳要給使用者看的原因。
    /// 行程的新增、修改、刪除都交給系統的編輯畫面，蒜日子自己寫進系統行事曆的只有這一件事。
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
