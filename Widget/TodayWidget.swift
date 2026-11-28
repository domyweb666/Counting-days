import EventKit
import SwiftUI
import WidgetKit
import CalendarCore

// 小工具「今天」：小尺寸，今天的日期和接下來的行程。
// 放哪幾筆、什麼時候換畫面的規則在 Core 的 WidgetRules，這裡只讀資料、畫出來。

struct TodayEntry: TimelineEntry {
    enum Content {
        case today(WidgetToday)
        /// 沒有行事曆的完整取用權限
        case noAccess
        /// 蒜日子抄過來的設定讀不回來
        case settingsUnreadable
    }

    let date: Date
    let calendar: Calendar
    let settings: AppSettings
    let content: Content
}

struct TodayProvider: TimelineProvider {
    /// 往後多查幾天。過午夜要換成明天，跨日行程排在第幾條又要看整週，所以查到下一週。
    private static let daysAhead = 9

    func placeholder(in context: Context) -> TodayEntry {
        let settings = AppSettings()
        return TodayEntry(
            date: .now,
            calendar: settings.displayCalendar(device: .current),
            settings: settings,
            content: .today(WidgetToday(rows: [], moreCount: 0))
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        Task { @MainActor in
            completion(Self.entries(from: .now)[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let next = now.addingTimeInterval(WidgetRules.refreshInterval)
            completion(Timeline(entries: Self.entries(from: now), policy: .after(next)))
        }
    }

    /// 從現在到明天結束，每次換畫面各一張。第一張是現在，至少有這一張。
    @MainActor
    private static func entries(from now: Date) -> [TodayEntry] {
        let settings: AppSettings
        do {
            settings = try readSettings()
        } catch {
            let fallback = AppSettings()
            return [TodayEntry(
                date: now,
                calendar: fallback.displayCalendar(device: .current),
                settings: fallback,
                content: .settingsUnreadable
            )]
        }

        let calendar = settings.displayCalendar(device: .current)
        let store = EventStore()
        guard store.hasAccess else {
            return [TodayEntry(date: now, calendar: calendar, settings: settings, content: .noAccess)]
        }
        store.displayTimeZone = calendar.timeZone
        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        let events = store.events(
            from: builder.startOfWeek(builder.today),
            to: builder.addDays(builder.today, daysAhead)
        )
        return WidgetRules.moments(events: events, now: now, calendar: calendar, settings: settings).map { moment in
            TodayEntry(
                date: moment,
                calendar: calendar,
                settings: settings,
                content: .today(WidgetRules.today(events: events, now: moment, calendar: calendar, settings: settings))
            )
        }
    }

    private struct SharedDrawerMissing: Error {}

    /// 蒜日子抄在共用抽屜裡的設定。其他六種小工具也讀這一份
    static func readSettings() throws -> AppSettings {
        guard let shared = UserDefaults(suiteName: WidgetShared.appGroupID) else { throw SharedDrawerMissing() }
        return try WidgetShared.settings(from: shared.data(forKey: WidgetShared.settingsKey))
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    private static let dowNames = ["日", "一", "二", "三", "四", "五", "六"]
    /// 一列前面那條類別色的寬與高
    private let barWidth: CGFloat = 4
    private let barHeight: CGFloat = 14
    /// 字放大時，一行放不下最多縮到幾成
    private let minimumScale: CGFloat = 0.8

    private var weekday: String {
        "週" + Self.dowNames[entry.calendar.component(.weekday, from: entry.date) - 1]
    }

    private var holiday: String? {
        guard case .today(let today) = entry.content else { return nil }
        return today.holiday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            header
            switch entry.content {
            case .today(let today):
                rows(today)
            case .noAccess:
                note("讀不到行事曆。打開蒜日子，允許取用行事曆。")
            case .settingsUnreadable:
                note("讀不到蒜日子的設定。打開蒜日子一次就會好。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .containerBackground(Theme.bg, for: .widget)
        .widgetURL(WidgetLink.today)
    }

    private var header: some View {
        HStack(spacing: DT.Space.s2) {
            Text(String(entry.calendar.component(.day, from: entry.date)))
                .dFont(DT.TypeScale.title1)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.calendar.component(.month, from: entry.date))月 \(weekday)")
                    .foregroundStyle(Theme.sub)
                if let holiday {
                    Text(holiday).foregroundStyle(Theme.destructive)
                }
            }
            .dFont(DT.TypeScale.caption)
        }
        .lineLimit(1)
        .minimumScaleFactor(minimumScale)
        .accessibilityElement(children: .combine)
    }

    /// 高度放不下三列就少列幾列，沒列的算進「還有幾筆」
    @ViewBuilder
    private func rows(_ today: WidgetToday) -> some View {
        if today.rows.isEmpty {
            note("接下來沒有行程")
        } else {
            ViewThatFits(in: .vertical) {
                list(today)
                list(today.limited(to: 2))
                list(today.limited(to: 1))
            }
        }
    }

    private func list(_ today: WidgetToday) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            ForEach(today.rows) { row($0) }
            if today.moreCount > 0 {
                Text("還有 \(today.moreCount) 筆")
                    .dFont(DT.TypeScale.caption)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            }
        }
    }

    private func row(_ row: WidgetRow) -> some View {
        HStack(spacing: DT.Space.s1) {
            RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                .fill(Theme.category(hex: entry.settings.category(id: row.categoryID).colorHex).fill)
                .frame(width: barWidth, height: barHeight)
                .accessibilityHidden(true)
            Text(row.timeText)
                .dFont(DT.TypeScale.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.sub)
                .fixedSize()
            Text(row.label)
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(minimumScale)
        }
        .lineLimit(1)
        // 手機鎖著、又在系統設定裡關掉鎖定時顯示，行程就遮起來
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dFont(DT.TypeScale.footnote)
            .foregroundStyle(Theme.sub)
            .minimumScaleFactor(minimumScale)
    }
}

// 小工具的進入點在 CalendarWidgets.swift 的 SuanRiZiWidgets，這一種也包在裡面
struct TodayWidget: Widget {
    /// 蒜日子叫小工具重畫時用這個名字指它，改了名字使用者主畫面上放好的那一塊會失效
    static let kind = "com.domyweb.countingdays.widget.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今天")
        .description("今天的日期和接下來的行程。")
        .supportedFamilies([.systemSmall])
    }
}
