import EventKit
import SwiftUI
import WidgetKit

// 小工具的骨架（第 60 片）：小尺寸，只畫今天的日期。
// 最下面那一行是探針，用來在手機上確認小工具這支程式讀不讀得到行事曆。
// Apple 文件沒有講小工具的情況，只能裝上去看。第 63 片換成真的行程時把探針拿掉。

/// 小工具這支程式讀不讀得到行事曆
enum CalendarProbe {
    case readable(todayCount: Int)
    case unreadable

    /// 權限不是完整存取、算不出今天的範圍，都當作讀不到。
    static func check(on day: Date) -> CalendarProbe {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .unreadable }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .unreadable }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return .readable(todayCount: store.events(matching: predicate).count)
    }

    var text: String {
        switch self {
        case .readable(let todayCount): return "讀得到行事曆，今天 \(todayCount) 筆"
        case .unreadable: return "讀不到行事曆"
        }
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let probe: CalendarProbe
}

struct TodayProvider: TimelineProvider {
    /// 算不出下一個午夜時，隔多久再重畫一次（秒）
    private static let fallbackRefresh: TimeInterval = 3600

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, probe: .unreadable)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        completion(TodayEntry(date: now, probe: CalendarProbe.check(on: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        // 過了午夜日期要換，所以排在下一個午夜重畫
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Self.fallbackRefresh)
        let entry = TodayEntry(date: now, probe: CalendarProbe.check(on: now))
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            Text(entry.date, format: .dateTime.weekday(.wide))
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
            Text(entry.date, format: .dateTime.month().day())
                .dFont(DT.TypeScale.title2)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Text(entry.probe.text)
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(Theme.sub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Theme.bg, for: .widget)
    }
}

@main
struct TodayWidget: Widget {
    /// 蒜日子叫小工具重畫時用這個名字指它，改了名字使用者主畫面上放好的那一塊會失效
    static let kind = "com.domyweb.countingdays.widget.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今天")
        .description("今天的日期。")
        .supportedFamilies([.systemSmall])
    }
}
