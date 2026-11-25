import SwiftUI
import WidgetKit
import CalendarCore

// 第 66 片起的六種小工具：小月曆（免費）、倒數日、彈性週、小月曆加接下來、整個月、鎖定畫面的下一件事（完整版）。
// 放哪幾筆、主事件、哪幾種要完整版都在 Core，這裡只讀資料、畫出來。

struct CalendarEntry: TimelineEntry {
    enum Content {
        case ready(events: [CalEvent])
        /// 沒買完整版（或問不到 App Store），只畫一句說明
        case locked
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

struct CalendarProvider: TimelineProvider {
    let style: WidgetStyle

    func placeholder(in context: Context) -> CalendarEntry {
        let settings = AppSettings()
        return CalendarEntry(
            date: .now,
            calendar: settings.displayCalendar(device: .current),
            settings: settings,
            content: .ready(events: [])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        Task { @MainActor in
            let isUnlocked = await PurchaseStore.checkUnlocked()
            completion(Self.entries(style: style, from: .now, isUnlocked: isUnlocked)[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        Task { @MainActor in
            // 每次重畫自己問 App Store，不讀蒜日子留下的紀錄，也不存。問不到就是沒買。
            let isUnlocked = await PurchaseStore.checkUnlocked()
            let now = Date()
            let next = now.addingTimeInterval(WidgetRules.refreshInterval)
            completion(Timeline(entries: Self.entries(style: style, from: now, isUnlocked: isUnlocked), policy: .after(next)))
        }
    }

    /// 從現在到明天結束，每次換畫面各一張。第一張是現在，至少有這一張。
    @MainActor
    private static func entries(style: WidgetStyle, from now: Date, isUnlocked: Bool) -> [CalendarEntry] {
        let settings: AppSettings
        do {
            settings = try TodayProvider.readSettings()
        } catch {
            let fallback = AppSettings()
            return [CalendarEntry(
                date: now, calendar: fallback.displayCalendar(device: .current), settings: fallback, content: .settingsUnreadable
            )]
        }
        let calendar = settings.displayCalendar(device: .current)
        guard FullVersionAccess.canShowWidget(style, isUnlocked: isUnlocked) else {
            return [CalendarEntry(date: now, calendar: calendar, settings: settings, content: .locked)]
        }
        let store = EventStore()
        guard store.hasAccess else {
            return [CalendarEntry(date: now, calendar: calendar, settings: settings, content: .noAccess)]
        }
        store.displayTimeZone = calendar.timeZone

        let builder = LayoutBuilder(calendar: calendar, today: now, settings: settings)
        // 從這個月 1 號那一週查起：月曆格子要畫整個月，跨日行程排第幾條也要看前面
        let monthStart = calendar.dateInterval(of: .month, for: builder.today)?.start ?? builder.today
        let daysAhead = style == .countdown ? WidgetRules.countdownDaysAhead : WidgetRules.upcomingDaysAhead + 7
        let events = store.events(
            from: builder.startOfWeek(monthStart),
            to: builder.addDays(builder.today, daysAhead)
        )
        return WidgetRules.moments(events: events, now: now, calendar: calendar, settings: settings).map {
            CalendarEntry(date: $0, calendar: calendar, settings: settings, content: .ready(events: events))
        }
    }
}

// MARK: - 共用的小東西

/// 字放大時，一行放不下最多縮到幾成
private let minimumScale: CGFloat = 0.6
/// 格子裡的小月曆、倒數日前面那個類別色小方塊的邊長
private let swatch: CGFloat = 10
/// 小月曆上今天那一圈的粗細。格子比蒜日子裡的小，用不了 Theme.Grid.ring 的 3
private let todayRing: CGFloat = 2
/// 不是這個月的日子淡到幾成，跟蒜日子清單樣式的小月曆一樣
private let otherMonthOpacity: Double = 0.35
private let dowNames = ["日", "一", "二", "三", "四", "五", "六"]
private let lockedText = "完整版的小工具。打開蒜日子看看。"

private func categoryColors(_ id: String, _ settings: AppSettings) -> (fill: Color, on: Color) {
    Theme.category(hex: settings.category(id: id).colorHex)
}

private func weekday(_ date: Date, _ calendar: Calendar) -> String {
    "週" + dowNames[calendar.component(.weekday, from: date) - 1]
}

private func weekdaySymbols(_ calendar: Calendar) -> [String] {
    (0..<7).map { dowNames[(calendar.firstWeekday - 1 + $0) % 7] }
}

private func isInMonth(_ date: Date, of today: Date, _ calendar: Calendar) -> Bool {
    calendar.isDate(date, equalTo: today, toGranularity: .month)
}

private func monthText(_ date: Date, _ calendar: Calendar) -> String {
    "\(calendar.component(.month, from: date))月"
}

/// 沒權限、設定讀不回來、沒買，各一句話
private struct WidgetNote: View {
    let text: String

    var body: some View {
        Text(text)
            .dFont(DT.TypeScale.footnote)
            .foregroundStyle(Theme.sub)
            .minimumScaleFactor(minimumScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 主畫面上的小工具共用的外框：先處理沒權限、沒買這些情況，有資料才畫內容
private struct HomeWidgetFrame<Content: View>: View {
    let entry: CalendarEntry
    @ViewBuilder let content: ([CalEvent]) -> Content

    var body: some View {
        Group {
            switch entry.content {
            case .ready(let events):
                content(events)
            case .locked:
                WidgetNote(text: lockedText)
            case .noAccess:
                WidgetNote(text: "讀不到行事曆。打開蒜日子，允許取用行事曆。")
            case .settingsUnreadable:
                WidgetNote(text: "讀不到蒜日子的設定。打開蒜日子一次就會好。")
            }
        }
        .padding(DT.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .containerBackground(Theme.card, for: .widget)
        .widgetURL(WidgetLink.today)
    }
}

// MARK: - 色塊小月曆（小C 免費、中C 左半邊）

/// 有行程的日子用那天主事件的類別色填滿（上面有跨日的就用跨日那一條），今天外框標出。
/// 跟蒜日子清單樣式的小月曆（MiniCell）同一套規則，判斷在 Core 的 `WidgetRules.monthMark`。
private struct MiniMonthGrid: View {
    let weeks: [WeekModel]
    let entry: CalendarEntry

    private let cellGap: CGFloat = 2

    var body: some View {
        VStack(spacing: cellGap) {
            ForEach(weeks) { week in
                HStack(spacing: cellGap) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { col, day in
                        cell(day, mark: WidgetRules.monthMark(in: week, col: col, settings: entry.settings))
                    }
                }
            }
        }
    }

    private func cell(_ day: DayModel, mark: WidgetMonthMark?) -> some View {
        let number = Text(String(entry.calendar.component(.day, from: day.date)))
            .sFont(11, .semibold)
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
        let shape = RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
        return ZStack {
            if let mark {
                let colors = categoryColors(mark.categoryID, entry.settings)
                shape.fill(day.isPast ? Theme.muted : colors.fill)
                number.foregroundStyle(day.isPast ? Theme.sub : colors.on)
            } else {
                number.foregroundStyle(
                    day.holidays.isEmpty ? (day.isPast ? Theme.tertiary : Theme.ink) : Theme.destructive
                )
            }
            if day.isToday {
                // 跟蒜日子一樣：今天有色塊時，外框和色塊中間壓一條卡片底色的縫
                shape.strokeBorder(Theme.card, lineWidth: todayRing + 1)
                shape.strokeBorder(Theme.accent, lineWidth: todayRing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isInMonth(day.date, of: entry.date, entry.calendar) ? 1 : otherMonthOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(day, mark: mark))
    }

    private func cellLabel(_ day: DayModel, mark: WidgetMonthMark?) -> String {
        var parts = ["\(entry.calendar.component(.day, from: day.date))日"]
        if day.isToday { parts.append("今天") }
        if let mark { parts.append(mark.label) }
        return parts.joined(separator: "，")
    }
}

struct SmallMonthView: View {
    let entry: CalendarEntry

    var body: some View {
        HomeWidgetFrame(entry: entry) { events in
            let weeks = WidgetRules.monthWeeks(events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings)
            VStack(alignment: .leading, spacing: DT.Space.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(monthText(entry.date, entry.calendar))
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    // 最後一週排到下個月時，告訴他後面那幾格是下個月
                    if let last = weeks.last?.days.last?.date, !isInMonth(last, of: entry.date, entry.calendar) {
                        Text("接著 " + monthText(last, entry.calendar))
                            .dFont(DT.TypeScale.caption)
                            .foregroundStyle(Theme.sub)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                MiniMonthGrid(weeks: weeks, entry: entry)
            }
        }
    }
}

// MARK: - 倒數日（小D 完整版）

struct CountdownView: View {
    let entry: CalendarEntry

    /// 天數的大字。設計系統最大的字級（34）撐不起這一塊，照設計稿放大
    private let numberSize: CGFloat = 56

    var body: some View {
        HomeWidgetFrame(entry: entry) { events in
            let ids = FullVersionAccess.visibleCountdowns(entry.settings.countdowns, isUnlocked: true)
            if let next = WidgetRules.nextCountdown(
                events: events, countdownIDs: ids, now: entry.date, calendar: entry.calendar, settings: entry.settings
            ) {
                content(next)
            } else {
                WidgetNote(text: "還沒有倒數日。打開蒜日子，在行程裡點「倒數日」。")
            }
        }
    }

    private func content(_ next: WidgetCountdown) -> some View {
        let color = categoryColors(next.categoryID, entry.settings).fill
        var footer = "\(entry.calendar.component(.month, from: next.date))月\(entry.calendar.component(.day, from: next.date))日 "
            + weekday(next.date, entry.calendar)
        if next.totalDays > 1 { footer += "，共 \(next.totalDays) 天" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DT.Space.s1) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: swatch, height: swatch)
                    .accessibilityHidden(true)
                Text(next.title)
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(minimumScale)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: DT.Space.s1) {
                Text(next.days == 0 ? "今天" : String(next.days))
                    .sFont(next.days == 0 ? numberSize / 2 : numberSize, .bold)
                    .foregroundStyle(color)
                if next.days > 0 {
                    Text("天後")
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            Spacer(minLength: 0)
            Text(footer)
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 彈性週（中A 完整版）

struct FlexWeekView: View {
    let entry: CalendarEntry

    private let bandHeight: CGFloat = 22
    private let gap: CGFloat = Theme.Grid.gap

    var body: some View {
        HomeWidgetFrame(entry: entry) { events in
            if let week = WidgetRules.weekFromToday(events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings) {
                VStack(spacing: DT.Space.s1) {
                    header(week)
                    let main = week.segments.filter { $0.band.lane == 0 }
                    if !main.isEmpty { bandRow(main) }
                    // 放不下就每天少列幾個，沒列的寫「+N」
                    ViewThatFits(in: .vertical) {
                        chips(week, limit: 3)
                        chips(week, limit: 2)
                        chips(week, limit: 1)
                        chips(week, limit: 0)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func header(_ week: WeekModel) -> some View {
        HStack(spacing: gap) {
            ForEach(week.days) { day in
                VStack(spacing: 0) {
                    Text(dayLabel(day.date))
                        .sFont(13, .semibold)
                        .foregroundStyle(day.isToday ? Theme.onAccent : (day.holidays.isEmpty ? Theme.ink : Theme.destructive))
                        .lineLimit(1)
                        .minimumScaleFactor(minimumScale)
                        .padding(.horizontal, gap)
                        .frame(minWidth: Theme.Grid.dayCircleSmall, minHeight: Theme.Grid.dayCircleSmall)
                        .background(Capsule().fill(day.isToday ? Theme.accent : Color.clear))
                    if let sub = WidgetRules.subline(for: day, calendar: entry.calendar, settings: entry.settings) {
                        Text(sub.text)
                            .sFont(10, .medium)
                            .foregroundStyle(sub.isHoliday ? Theme.destructive : Theme.sub)
                            .lineLimit(1)
                            .minimumScaleFactor(minimumScale)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// 每月 1 號寫成「12/1」，其餘只寫日，跟蒜日子的月曆一樣
    private func dayLabel(_ date: Date) -> String {
        let c = entry.calendar.dateComponents([.month, .day], from: date)
        return c.day == 1 ? "\(c.month ?? 0)/1" : String(c.day ?? 0)
    }

    /// 最上面那一條跨日的色帶。其他條放不下，算進每天的「+N」
    private func bandRow(_ segments: [BandSegment]) -> some View {
        GeometryReader { geo in
            let colW = (geo.size.width - gap * 6) / 7
            ForEach(segments) { seg in
                let colors = categoryColors(seg.band.categoryID, entry.settings)
                HStack(spacing: DT.Space.s1) {
                    Text(CellText.label(title: seg.band.event.title, shortName: entry.settings.shortNames[seg.band.event.seriesID]))
                        .sFont(13, .semibold)
                    Spacer(minLength: 0)
                    if seg.span >= 3, seg.startsHere {
                        Text("共 \(seg.band.totalDays) 天").sFont(11, .semibold)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .foregroundStyle(colors.on)
                .padding(.horizontal, DT.Space.s2)
                .frame(width: CGFloat(seg.span) * colW + CGFloat(seg.span - 1) * gap, height: bandHeight)
                .background(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous).fill(colors.fill))
                .offset(x: CGFloat(seg.startCol) * (colW + gap))
            }
        }
        .frame(height: bandHeight)
        .accessibilityElement(children: .combine)
    }

    private func chips(_ week: WeekModel, limit: Int) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(week.days) { day in
                let shown = Array(day.events.prefix(limit))
                let more = day.events.count - shown.count + day.bands.filter { $0.lane > 0 }.count
                VStack(spacing: gap) {
                    ForEach(shown) { e in
                        let colors = categoryColors(e.categoryID, entry.settings)
                        Text(e.label)
                            .sFont(11, .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(minimumScale)
                            .foregroundStyle(colors.on)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous).fill(colors.fill))
                    }
                    if more > 0 {
                        Text("+\(more)")
                            .sFont(10, .semibold)
                            .foregroundStyle(Theme.sub)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 小月曆加接下來（中C 完整版）

struct MonthNextView: View {
    let entry: CalendarEntry

    var body: some View {
        HomeWidgetFrame(entry: entry) { events in
            let weeks = WidgetRules.monthWeeks(events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings)
            let cards = WidgetRules.upcoming(
                events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings, count: WidgetRules.smallRowLimit
            )
            HStack(spacing: DT.Space.s3) {
                VStack(alignment: .leading, spacing: DT.Space.s1) {
                    Text(monthText(entry.date, entry.calendar))
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    MiniMonthGrid(weeks: weeks, entry: entry)
                }
                .frame(maxWidth: .infinity)
                Group {
                    if cards.isEmpty {
                        WidgetNote(text: "接下來沒有行程")
                    } else {
                        ViewThatFits(in: .vertical) {
                            list(cards)
                            list(Array(cards.prefix(2)))
                            list(Array(cards.prefix(1)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func list(_ cards: [UpcomingCard]) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            ForEach(cards) { row($0) }
        }
    }

    private func row(_ card: UpcomingCard) -> some View {
        let line = text(card)
        return VStack(alignment: .leading, spacing: 0) {
            Text(when(card))
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(Theme.sub)
            HStack(spacing: DT.Space.s1) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(categoryColors(line.categoryID, entry.settings).fill)
                    .frame(width: swatch, height: swatch)
                    .accessibilityHidden(true)
                Text(line.text)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.ink)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(minimumScale)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    /// 「今天」「進行中」，或「28 週六，2 天後」
    private func when(_ card: UpcomingCard) -> String {
        if card.daysAway <= 0 { return card.awayText }
        return "\(entry.calendar.component(.day, from: card.date)) \(weekday(card.date, entry.calendar))，\(card.awayText)"
    }

    /// 那一天的主事件「10:00 錄影」，跨日的「台南行，3 天」
    private func text(_ card: UpcomingCard) -> (text: String, categoryID: String) {
        switch card.kind {
        case .day(let day):
            guard let head = day.head else { return ("", "") }
            let builder = LayoutBuilder(calendar: entry.calendar, today: entry.date, settings: entry.settings)
            return ("\(builder.timeText(head.event)) \(head.label)", head.categoryID)
        case .band(let band):
            let label = CellText.label(title: band.event.title, shortName: entry.settings.shortNames[band.event.seriesID])
            return ("\(label)，\(band.totalDays) 天", band.categoryID)
        }
    }
}

// MARK: - 整個月（大A 完整版）

struct LargeMonthView: View {
    let entry: CalendarEntry

    private let gap: CGFloat = Theme.Grid.gap
    /// 今天那一格的實心圓。六週的月份要塞得下，比蒜日子裡的 26 小
    private let numberCircle: CGFloat = 22

    var body: some View {
        HomeWidgetFrame(entry: entry) { events in
            let weeks = WidgetRules.monthWeeks(events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings)
            VStack(spacing: DT.Space.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(monthText(entry.date, entry.calendar))
                        .dFont(DT.TypeScale.title3)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Text(todayText)
                        .dFont(DT.TypeScale.caption)
                        .foregroundStyle(Theme.sub)
                }
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .padding(.horizontal, DT.Space.s1)
                HStack(spacing: gap) {
                    ForEach(weekdaySymbols(entry.calendar), id: \.self) { s in
                        Text(s).dFont(DT.TypeScale.caption).foregroundStyle(Theme.sub).frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                VStack(spacing: gap) {
                    ForEach(weeks) { week in
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(Array(week.days.enumerated()), id: \.element.id) { col, day in
                                cell(day, mark: WidgetRules.monthMark(in: week, col: col, settings: entry.settings))
                            }
                        }
                    }
                }
            }
        }
    }

    /// 右上角：「今天 農曆十月十八」；設定關掉農曆就只寫「今天 26日」
    private var todayText: String {
        guard entry.settings.showLunar else { return "今天 \(entry.calendar.component(.day, from: entry.date))日" }
        let lunar = Lunar.lunarDay(for: entry.calendar.startOfDay(for: entry.date).addingTimeInterval(12 * 3600), timeZone: entry.calendar.timeZone)
        return "今天 " + lunar.fullText
    }

    private func cell(_ day: DayModel, mark: WidgetMonthMark?) -> some View {
        let c = entry.calendar.dateComponents([.month, .day], from: day.date)
        let label = c.day == 1 ? "\(c.month ?? 0)/1" : String(c.day ?? 0)
        return VStack(spacing: 2) {
            Text(label)
                .sFont(13, .semibold)
                .foregroundStyle(numberColor(day))
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .padding(.horizontal, 2)
                .frame(minWidth: numberCircle, minHeight: numberCircle)
                .background(Capsule().fill(day.isToday ? Theme.accent : Color.clear))
            if let mark {
                let colors = categoryColors(mark.categoryID, entry.settings)
                Text(mark.label)
                    .sFont(11, .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(minimumScale)
                    .foregroundStyle(day.isPast ? Theme.sub : colors.on)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous).fill(day.isPast ? Theme.muted : colors.fill))
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isInMonth(day.date, of: entry.date, entry.calendar) ? 1 : otherMonthOpacity)
        .accessibilityElement(children: .combine)
    }

    private func numberColor(_ day: DayModel) -> Color {
        if day.isToday { return Theme.onAccent }
        if !day.holidays.isEmpty { return Theme.destructive }
        return day.isPast ? Theme.tertiary : Theme.ink
    }
}

// MARK: - 鎖定畫面的下一件事（鎖A 完整版）

/// 鎖定畫面只有單色，類別顏色用不上，靠字的大小粗細分：上一行時間、中間大字名字、下一行接著哪件
struct LockNextView: View {
    let entry: CalendarEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch entry.content {
            case .ready(let events):
                let today = WidgetRules.today(events: events, now: entry.date, calendar: entry.calendar, settings: entry.settings, limit: 2)
                if let first = today.rows.first {
                    Text("今天 " + first.timeText).dFont(DT.TypeScale.caption)
                    Text(first.label).dFont(DT.TypeScale.headline).privacySensitive()
                    if today.rows.count > 1 {
                        let second = today.rows[1]
                        Text("接著 \(second.timeText) \(second.label)").dFont(DT.TypeScale.caption).privacySensitive()
                    }
                } else {
                    Text("今天").dFont(DT.TypeScale.caption)
                    Text("接下來沒有行程").dFont(DT.TypeScale.headline)
                }
            case .locked:
                Text("完整版的小工具").dFont(DT.TypeScale.headline)
                Text("打開蒜日子看看").dFont(DT.TypeScale.caption)
            case .noAccess:
                Text("讀不到行事曆").dFont(DT.TypeScale.headline)
                Text("打開蒜日子允許取用").dFont(DT.TypeScale.caption)
            case .settingsUnreadable:
                Text("讀不到設定").dFont(DT.TypeScale.headline)
                Text("打開蒜日子一次").dFont(DT.TypeScale.caption)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(minimumScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .containerBackground(Color.clear, for: .widget)
        .widgetURL(WidgetLink.today)
    }
}

// MARK: - 六種小工具

/// 種類名 = 這個前綴 + `WidgetStyle` 的 rawValue。上架後不能改
private func widgetKind(_ style: WidgetStyle) -> String {
    "com.domyweb.countingdays.widget." + style.rawValue
}

struct SmallMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.smallMonth), provider: CalendarProvider(style: .smallMonth)) {
            SmallMonthView(entry: $0)
        }
        .configurationDisplayName("小月曆")
        .description("這個月哪幾天有事，顏色照類別。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.countdown), provider: CalendarProvider(style: .countdown)) {
            CountdownView(entry: $0)
        }
        .configurationDisplayName("倒數日")
        .description("最快到的那一個倒數日還有幾天。完整版才看得到。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct FlexWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.flexWeek), provider: CalendarProvider(style: .flexWeek)) {
            FlexWeekView(entry: $0)
        }
        .configurationDisplayName("彈性週")
        .description("從今天起七天的行程。完整版才看得到。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct MonthNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.monthNext), provider: CalendarProvider(style: .monthNext)) {
            MonthNextView(entry: $0)
        }
        .configurationDisplayName("小月曆與接下來")
        .description("這個月的小月曆，加上接下來三件事。完整版才看得到。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct LargeMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.largeMonth), provider: CalendarProvider(style: .largeMonth)) {
            LargeMonthView(entry: $0)
        }
        .configurationDisplayName("整個月")
        .description("這個月每天最重要的那件事。完整版才看得到。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct LockNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind(.lockNext), provider: CalendarProvider(style: .lockNext)) {
            LockNextView(entry: $0)
        }
        .configurationDisplayName("下一件事")
        .description("今天接下來的那一件，放在鎖定畫面。完整版才看得到。")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct SuanRiZiWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        SmallMonthWidget()
        CountdownWidget()
        FlexWeekWidget()
        MonthNextWidget()
        LargeMonthWidget()
        LockNextWidget()
    }
}
