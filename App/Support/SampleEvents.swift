import Foundation
import CalendarCore

/// 主題頁、月曆樣式頁的預覽用的範例行程。只活在記憶體裡，不會寫進系統行事曆。
enum SampleEvents {
    /// 範例行程掛在這幾本假的行事曆上，各自對到一個預設類別
    static let calendarCategory: [String: String] = [
        "demo.work": "work",
        "demo.life": "life",
        "demo.fun": "fun",
        "demo.rest": "rest"
    ]

    /// 從今天起三週內的範例行程
    static func events(today: Date, calendar: Calendar) -> [CalEvent] {
        let start = calendar.startOfDay(for: today)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }
        func at(_ offset: Int, _ hour: Double) -> Date {
            day(offset).addingTimeInterval(hour * 3600)
        }
        func timed(_ id: String, _ title: String, _ cal: String, _ offset: Int,
                   _ from: Double, _ to: Double, location: String? = nil) -> CalEvent {
            CalEvent(id: "demo." + id, title: title, start: at(offset, from), end: at(offset, to),
                     calendarID: cal, location: location)
        }

        return [
            timed("record", "錄影", "demo.work", 0, 10, 12),
            timed("mail", "回覆合作信", "demo.work", 0, 14, 14.5),
            timed("dentist", "牙醫", "demo.life", 2, 15.5, 16.5, location: "安和牙醫"),
            timed("draft", "交稿", "demo.work", 4, 12, 13),
            timed("parcel", "領包裹", "demo.life", 4, 17, 17.5),
            timed("dinner", "聚餐", "demo.fun", 6, 18.5, 21, location: "永康街"),
            timed("spa", "按摩", "demo.rest", 8, 15, 16),
            timed("live", "直播", "demo.work", 9, 20, 21.5),
            CalEvent(id: "demo.tainan", title: "台南行", start: day(11),
                     end: day(14).addingTimeInterval(-1), isAllDay: true, calendarID: "demo.fun")
        ]
    }
}
