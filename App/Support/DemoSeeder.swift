#if DEBUG
import EventKit
import Foundation
import CalendarCore

/// 拍上架截圖、錄審核影片用的示範行程。只在 Debug 建置裡，上架的版本沒有這段。
/// 用法：模擬器先給行事曆權限，再用環境變數 `SUANRIZI_DEMO=1` 啟動 app。
/// 會在「本機」建四本行事曆（工作、生活、娛樂、台灣節日），塞今天前後三週的假行程。已經建過就不再建。
@MainActor
enum DemoSeeder {
    static let flag = "SUANRIZI_DEMO"

    static func runIfAsked(store: EventStore, settings: SettingsStore) {
        guard ProcessInfo.processInfo.environment[flag] == "1",
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let ek = store.ek
        guard let source = ek.sources.first(where: { $0.sourceType == .local })
                ?? ek.defaultCalendarForNewEvents?.source else { return }
        let existing = ek.calendars(for: .event)
        if existing.contains(where: { $0.title == "工作" && $0.source == source }) {
            applySettings(ek: ek, settings: settings)
            return
        }

        func makeCalendar(_ title: String, _ hex: String) -> EKCalendar? {
            let cal = EKCalendar(for: .event, eventStore: ek)
            cal.title = title
            cal.source = source
            cal.cgColor = color(hex)
            do { try ek.saveCalendar(cal, commit: true) } catch { return nil }
            return cal
        }
        guard let work = makeCalendar("工作", "#6F5F8F"),
              let life = makeCalendar("生活", "#4B6C8F"),
              let fun = makeCalendar("娛樂", "#A65F45"),
              let holiday = makeCalendar("台灣節日", "#E07A3F") else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }
        func at(_ offset: Int, _ hour: Double) -> Date { day(offset).addingTimeInterval(hour * 3600) }

        @discardableResult
        func timed(_ title: String, _ calendar: EKCalendar, _ offset: Int, _ from: Double, _ to: Double,
                   location: String? = nil) -> EKEvent {
            let e = EKEvent(eventStore: ek)
            e.title = title
            e.calendar = calendar
            e.startDate = at(offset, from)
            e.endDate = at(offset, to)
            e.location = location
            try? ek.save(e, span: .thisEvent, commit: false)
            return e
        }
        @discardableResult
        func allDay(_ title: String, _ calendar: EKCalendar, from: Date, days: Int = 1) -> EKEvent {
            let e = EKEvent(eventStore: ek)
            e.title = title
            e.calendar = calendar
            e.isAllDay = true
            e.startDate = from
            e.endDate = cal.date(byAdding: .day, value: days - 1, to: from) ?? from
            try? ek.save(e, span: .thisEvent, commit: false)
            return e
        }

        timed("讀書會", fun, -5, 19.5, 21)
        timed("剪頭髮", life, -2, 11, 12)
        timed("錄影", work, 0, 10, 12)
        timed("回覆合作信", work, 0, 14, 14.5)
        timed("健身", life, 1, 19, 20)
        timed("牙醫", life, 2, 15.5, 16.5, location: "安和牙醫診所")
        timed("交稿", work, 3, 12, 13)
        timed("領包裹", life, 3, 17, 17.5)
        timed("聚餐", fun, 5, 18.5, 21, location: "永康街")
        timed("直播", work, 7, 20, 21.5)
        timed("按摩", life, 8, 15, 16)
        allDay("台南行", fun, from: day(10), days: 3)
        allDay("媽媽生日", life, from: day(15))
        timed("開會", work, 16, 10, 11)
        timed("看展", fun, 18, 14, 16, location: "北美館")
        timed("繳房租", life, 20, 9, 9.5)

        // 台灣節日：今天前後幾個月裡固定日期的國定假日
        let year = cal.component(.year, from: today)
        for (y, m, d, name) in [(year, 10, 10, "國慶日"), (year, 11, 12, "國父誕辰紀念日"),
                                (year, 12, 25, "行憲紀念日"), (year + 1, 1, 1, "開國紀念日")] {
            if let date = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                allDay(name, holiday, from: date)
            }
        }
        try? ek.commit()
        applySettings(ek: ek, settings: settings)
    }

    /// 四本示範行事曆對到類別、節日；台南行、媽媽生日放進倒數日；示範以外的行事曆從蒜日子移除（手機上還在）
    private static func applySettings(ek: EKEventStore, settings: SettingsStore) {
        let calendars = ek.calendars(for: .event)
        func id(_ title: String) -> String? {
            calendars.first { $0.title == title && $0.source.sourceType == .local }?.calendarIdentifier
        }
        guard let work = id("工作"), let life = id("生活"), let fun = id("娛樂"), let holiday = id("台灣節日") else { return }
        let demo: Set<String> = [work, life, fun, holiday]
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 60, to: today) ?? today
        let found = ek.events(matching: ek.predicateForEvents(withStart: today, end: end, calendars: nil))
        let countdownIDs = ["台南行", "媽媽生日"].compactMap { title in
            found.first { $0.title == title }?.eventIdentifier
        }
        settings.update { s in
            s.calendarCategory[work] = "work"
            s.calendarCategory[life] = "life"
            s.calendarCategory[fun] = "fun"
            s.holidayCalendarIDs.insert(holiday)
            s.hiddenCalendarIDs = Set(calendars.map(\.calendarIdentifier)).subtracting(demo)
            for id in countdownIDs where !s.countdowns.contains(id) {
                s.countdowns.append(id)
            }
        }
    }

    private static func color(_ hex: String) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(
            red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1
        )
    }
}
#endif
