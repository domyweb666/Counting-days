import Foundation

/// 最上層的檢視。月曆的四種畫法是 DisplayMode，只在 month 底下有用。
/// 這裡的先後就是側邊欄由上到下的順序：時間表、天、3 天、週、月。
public enum ViewKind: String, Codable, CaseIterable, Sendable {
    case agenda
    case day
    case threeDay
    case week
    case month

    public var label: String {
        switch self {
        case .month: return "月"
        case .agenda: return "時間表"
        case .week: return "週"
        case .threeDay: return "3 天"
        case .day: return "天"
        }
    }

    /// 時間軸一次排幾天；月曆與時間表不是時間軸，回傳 nil
    public var dayCount: Int? {
        switch self {
        case .week: return 7
        case .threeDay: return 3
        case .day: return 1
        case .month, .agenda: return nil
        }
    }
}

/// 時間軸上的一塊行程
public struct TimeBlock: Identifiable, Hashable, Sendable {
    public var event: ClassifiedEvent
    /// 從當天 00:00 起算的分鐘數
    public var startMinute: Int
    public var endMinute: Int
    /// 跟別的行程重疊時排在第幾欄
    public var column: Int
    /// 這一群重疊的行程總共分成幾欄
    public var columnCount: Int

    public var id: String { event.id }
}

extension LayoutBuilder {
    public static let minutesPerDay = 24 * 60

    public func endTimeText(_ event: CalEvent) -> String {
        if event.isAllDay { return "" }
        let c = calendar.dateComponents([.hour, .minute], from: event.end)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 這一天有時間的行程（含每日例行事件，時間軸上它們也佔時間）
    public func timedEvents(for day: DayModel) -> [ClassifiedEvent] {
        (day.events + day.routines).filter { !$0.event.isAllDay }
    }

    /// 這一天的單日全天行程（跨日的在 day.bands）
    public func allDayEvents(for day: DayModel) -> [ClassifiedEvent] {
        day.events.filter { $0.event.isAllDay }
    }

    /// 把一天裡有時間的行程排成時間軸：重疊的並排。
    /// 太短的行程畫成 minimumMinutes 那麼高，才點得到、讀得到字。
    /// 跨過午夜的行程只畫到當天 24:00。
    public func timeBlocks(for day: DayModel, minimumMinutes: Int = 30) -> [TimeBlock] {
        let limit = LayoutBuilder.minutesPerDay
        let minimum = max(1, min(minimumMinutes, limit))

        var blocks: [TimeBlock] = timedEvents(for: day).map { e in
            let c = calendar.dateComponents([.hour, .minute], from: e.event.start)
            var start = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let duration = max(0, Int((e.event.end.timeIntervalSince(e.event.start) / 60).rounded()))
            var end = min(start + max(duration, minimum), limit)
            if end - start < minimum {
                start = max(0, limit - minimum)
                end = limit
            }
            return TimeBlock(event: e, startMinute: start, endMinute: end, column: 0, columnCount: 1)
        }
        blocks.sort {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.id < $1.id
        }

        var result: [TimeBlock] = []
        var cluster: [TimeBlock] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func flush() {
            for var b in cluster {
                b.columnCount = columnEnds.count
                result.append(b)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for var b in blocks {
            if !cluster.isEmpty, b.startMinute >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= b.startMinute }) {
                b.column = free
                columnEnds[free] = b.endMinute
            } else {
                b.column = columnEnds.count
                columnEnds.append(b.endMinute)
            }
            clusterEnd = max(clusterEnd, b.endMinute)
            cluster.append(b)
        }
        flush()
        return result
    }

    /// 時間表要列的日子：今天起有行程的每一天。今天沒事也列，讓畫面有個起點。
    public func agendaDays(in weeks: [WeekModel]) -> [DayModel] {
        weeks.flatMap(\.days).filter { day in
            day.date >= today && (day.isToday || day.hasEvents || !day.bands.isEmpty)
        }
    }
}
