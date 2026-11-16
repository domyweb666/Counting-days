import Foundation

/// 把一堆事件排成「一週一週」的版面資料。四種呈現方式都吃這一份。
public struct LayoutBuilder: Sendable {
    public let calendar: Calendar
    public let today: Date
    public let settings: AppSettings

    public init(calendar: Calendar, today: Date, settings: AppSettings) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: today)
        self.settings = settings
    }

    // MARK: 日期工具

    public func startOfWeek(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return addDays(day, -offset)
    }

    public func addDays(_ date: Date, _ n: Int) -> Date {
        guard let d = calendar.date(byAdding: .day, value: n, to: date) else {
            preconditionFailure("日期加減失敗：\(date) + \(n) 天")
        }
        return d
    }

    public func dayDistance(from a: Date, to b: Date) -> Int {
        let comps = calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b))
        return comps.day ?? 0
    }

    /// 事件涵蓋的最後一天。結束時間剛好落在午夜的，不算進隔天。
    func lastDay(of event: CalEvent) -> Date {
        guard event.end > event.start else { return calendar.startOfDay(for: event.start) }
        return calendar.startOfDay(for: event.end.addingTimeInterval(-1))
    }

    /// 跨日事件：跨過一天以上，而且是全天事件或長度滿 24 小時。
    /// 晚上 11 點到凌晨 1 點這種不算，照單日事件放在開始那天。
    func isMultiDay(_ event: CalEvent) -> Bool {
        let first = calendar.startOfDay(for: event.start)
        guard lastDay(of: event) > first else { return false }
        return event.isAllDay || event.end.timeIntervalSince(event.start) >= 24 * 3600
    }

    // MARK: 組版面

    public func weeks(from rangeStart: Date, to rangeEnd: Date, events: [CalEvent]) -> [WeekModel] {
        let first = startOfWeek(rangeStart)
        let lastWeekStart = startOfWeek(rangeEnd)
        guard lastWeekStart >= first else { return [] }

        var singles: [Date: [ClassifiedEvent]] = [:]
        var routines: [Date: [ClassifiedEvent]] = [:]
        var holidays: [Date: [String]] = [:]
        var bands: [Band] = []

        for event in events {
            if settings.hiddenCalendarIDs.contains(event.calendarID) { continue }
            let firstDay = calendar.startOfDay(for: event.start)

            if settings.holidayCalendarIDs.contains(event.calendarID) {
                let last = lastDay(of: event)
                var d = firstDay
                while d <= last {
                    if !(holidays[d] ?? []).contains(event.title) {
                        holidays[d, default: []].append(event.title)
                    }
                    d = addDays(d, 1)
                }
                continue
            }

            let categoryID = Classifier.categoryID(for: event, settings: settings)

            if isMultiDay(event) {
                let last = lastDay(of: event)
                bands.append(Band(
                    event: event,
                    categoryID: categoryID,
                    firstDay: firstDay,
                    lastDay: last,
                    totalDays: dayDistance(from: firstDay, to: last) + 1,
                    lane: 0
                ))
                continue
            }

            let classified = ClassifiedEvent(
                event: event,
                categoryID: categoryID,
                label: CellText.label(title: event.title, shortName: settings.shortNames[event.seriesID]),
                isPinned: settings.pinned.contains(event.seriesID)
            )
            if event.isDailyRoutine {
                routines[firstDay, default: []].append(classified)
            } else {
                singles[firstDay, default: []].append(classified)
            }
        }

        bands = assignLanes(bands)

        var result: [WeekModel] = []
        var weekStart = first
        while weekStart <= lastWeekStart {
            let weekEnd = addDays(weekStart, 6)
            var days: [DayModel] = []
            for i in 0..<7 {
                let date = addDays(weekStart, i)
                let evs = (singles[date] ?? []).sorted(by: eventOrder)
                let head = HeadPicker.pick(evs, settings: settings)
                days.append(DayModel(
                    date: date,
                    events: evs,
                    routines: (routines[date] ?? []).sorted(by: eventOrder),
                    head: head,
                    rest: evs.filter { $0.id != head?.id },
                    holidays: holidays[date] ?? [],
                    bands: bands.filter { $0.firstDay <= date && date <= $0.lastDay },
                    isPast: date < today,
                    isToday: date == today
                ))
            }
            let segments: [BandSegment] = bands
                .filter { $0.firstDay <= weekEnd && $0.lastDay >= weekStart }
                .map { band in
                    let s = max(band.firstDay, weekStart)
                    let e = min(band.lastDay, weekEnd)
                    return BandSegment(
                        band: band,
                        startCol: dayDistance(from: weekStart, to: s),
                        endCol: dayDistance(from: weekStart, to: e),
                        startsHere: band.firstDay >= weekStart,
                        endsHere: band.lastDay <= weekEnd,
                        isPast: band.lastDay < today
                    )
                }
                .sorted { $0.band.lane < $1.band.lane }
            result.append(WeekModel(days: days, segments: segments, isAllPast: weekEnd < today))
            weekStart = addDays(weekStart, 7)
        }
        return result
    }

    /// 一天裡的行程誰排前面：全天的先，再照開始時間；開始時間一樣，照使用者排的行事曆順序。
    func eventOrder(_ a: ClassifiedEvent, _ b: ClassifiedEvent) -> Bool {
        if a.event.isAllDay != b.event.isAllDay { return a.event.isAllDay }
        if a.event.start != b.event.start { return a.event.start < b.event.start }
        let ca = CalendarOrder.rank(of: a.event.calendarID, in: settings.calendarOrder)
        let cb = CalendarOrder.rank(of: b.event.calendarID, in: settings.calendarOrder)
        if ca != cb { return ca < cb }
        return a.event.id < b.event.id
    }

    /// 重疊的跨日事件分到不同條。先開始的、比較長的排前面。
    func assignLanes(_ input: [Band]) -> [Band] {
        let sorted = input.sorted {
            if $0.firstDay != $1.firstDay { return $0.firstDay < $1.firstDay }
            if $0.totalDays != $1.totalDays { return $0.totalDays > $1.totalDays }
            return $0.id < $1.id
        }
        var laneEnds: [Date] = []
        var out: [Band] = []
        for var band in sorted {
            if let free = laneEnds.firstIndex(where: { $0 < band.firstDay }) {
                band.lane = free
                laneEnds[free] = band.lastDay
            } else {
                band.lane = laneEnds.count
                laneEnds.append(band.lastDay)
            }
            out.append(band)
        }
        return out
    }
}

// MARK: - 點一天展開的時間表

public struct DetailRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case band(dayNumber: Int, totalDays: Int)
        case head
        case normal
        case routine
    }

    public var kind: Kind
    public var timeText: String
    public var title: String
    public var categoryID: String
    public var event: CalEvent
    public var isPinned: Bool

    public var id: String { event.id }
}

extension LayoutBuilder {
    public func timeText(_ event: CalEvent) -> String {
        if event.isAllDay { return "全天" }
        let c = calendar.dateComponents([.hour, .minute], from: event.start)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    public func detailRows(for day: DayModel) -> [DetailRow] {
        var rows: [DetailRow] = []
        for band in day.bands.sorted(by: { $0.lane < $1.lane }) {
            let n = dayDistance(from: band.firstDay, to: day.date) + 1
            rows.append(DetailRow(
                kind: .band(dayNumber: n, totalDays: band.totalDays),
                timeText: "全天",
                title: band.event.title,
                categoryID: band.categoryID,
                event: band.event,
                isPinned: false
            ))
        }
        for e in day.events {
            rows.append(DetailRow(
                kind: e.id == day.head?.id ? .head : .normal,
                timeText: timeText(e.event),
                title: e.event.title,
                categoryID: e.categoryID,
                event: e.event,
                isPinned: e.isPinned
            ))
        }
        for e in day.routines {
            rows.append(DetailRow(
                kind: .routine,
                timeText: timeText(e.event),
                title: e.event.title,
                categoryID: e.categoryID,
                event: e.event,
                isPinned: false
            ))
        }
        return rows
    }
}

// MARK: - 週條（C）

public enum StripItem: Identifiable, Hashable, Sendable {
    /// 沒事的日子：窄條
    case narrow(DayModel)
    /// 有事的日子：撐開的卡片，列出完整標題
    case card(DayModel)
    /// 一週有 4 天以上有事：精簡卡
    case compact(DayModel)
    /// 跨日事件在這一週合併成一整塊
    case trip(BandSegment)

    public var id: String {
        switch self {
        case .narrow(let d): return "n\(d.date.timeIntervalSinceReferenceDate)"
        case .card(let d): return "c\(d.date.timeIntervalSinceReferenceDate)"
        case .compact(let d): return "k\(d.date.timeIntervalSinceReferenceDate)"
        case .trip(let s): return "t" + s.id
        }
    }
}

extension LayoutBuilder {
    public static let compactThreshold = 4

    public func stripItems(for week: WeekModel) -> [StripItem] {
        // 只有最上面那一條跨日事件會合併成整塊，其餘的在點開當天時看得到。
        let main = week.segments.first { $0.band.lane == 0 }
        func inTrip(_ col: Int) -> Bool {
            guard let main else { return false }
            return col >= main.startCol && col <= main.endCol
        }
        let busyDays = week.days.enumerated().filter { !inTrip($0.offset) && $0.element.hasEvents }.count
        let compact = busyDays >= LayoutBuilder.compactThreshold

        var items: [StripItem] = []
        for (col, day) in week.days.enumerated() {
            if inTrip(col) {
                if let main, col == main.startCol { items.append(.trip(main)) }
                continue
            }
            if day.hasEvents {
                items.append(compact ? .compact(day) : .card(day))
            } else {
                items.append(.narrow(day))
            }
        }
        return items
    }
}

// MARK: - 「接下來」清單（B）

public struct UpcomingCard: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case day(DayModel)
        case band(Band)
    }

    public var kind: Kind
    public var date: Date
    /// 0 是今天；跨日事件已經開始的話是負數
    public var daysAway: Int

    public var id: String {
        switch kind {
        case .day(let d): return "d\(d.date.timeIntervalSinceReferenceDate)"
        case .band(let b): return "b" + b.id
        }
    }

    public var awayText: String {
        if daysAway < 0 { return "進行中" }
        if daysAway == 0 { return "今天" }
        if daysAway == 1 { return "明天" }
        return "\(daysAway) 天後"
    }
}

extension LayoutBuilder {
    public func upcoming(in weeks: [WeekModel], limit: Int = 60) -> [UpcomingCard] {
        var cards: [UpcomingCard] = []
        var seenBands = Set<String>()
        for week in weeks {
            for day in week.days where day.date >= today {
                for band in day.bands.sorted(by: { $0.lane < $1.lane }) where !seenBands.contains(band.id) {
                    seenBands.insert(band.id)
                    cards.append(UpcomingCard(
                        kind: .band(band),
                        date: band.firstDay,
                        daysAway: dayDistance(from: today, to: band.firstDay)
                    ))
                }
                if day.hasEvents {
                    cards.append(UpcomingCard(
                        kind: .day(day),
                        date: day.date,
                        daysAway: dayDistance(from: today, to: day.date)
                    ))
                }
                if cards.count >= limit { return cards }
            }
        }
        return cards
    }
}
