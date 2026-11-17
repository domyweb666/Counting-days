import Foundation

/// 蒜日子與小工具共用的抽屜（App Group）。蒜日子每次存設定多寫一份進去，小工具只讀。
/// 裡面只放設定，「買了沒」不准放。
public enum WidgetShared {
    /// 要跟 project.yml 兩支程式的權利宣告、Apple 開發者後台的 App Group 一樣
    public static let appGroupID = "group.com.domyweb.countingdays"
    /// 抽屜裡放設定的那一格，內容是 AppSettings 的 JSON
    public static let settingsKey = "settings.v1"
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
}

/// 小工具上要放哪幾筆。哪些行程算今天的、誰排前面，都跟蒜日子裡點開今天看到的一樣（用同一個 LayoutBuilder），
/// 只多兩條：已經結束的不放、每天重複的例行事件不放。
/// 順序：跨日的、全天的、有時間的照開始時間。
public enum WidgetRules {
    /// 小尺寸最多列幾筆
    public static let smallRowLimit = 3

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
        return WidgetToday(rows: Array(rows.prefix(shown)), moreCount: max(0, rows.count - shown))
    }
}
