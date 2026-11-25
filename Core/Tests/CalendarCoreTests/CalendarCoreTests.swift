import XCTest
@testable import CalendarCore

final class CalendarCoreTests: XCTestCase {
    var cal: Calendar!
    var settings: AppSettings!

    override func setUp() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        c.firstWeekday = 1
        cal = c
        settings = AppSettings(calendarCategory: ["W": "work", "M": "life", "E": "rest"], holidayCalendarIDs: ["H"])
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func ev(_ id: String, _ title: String, _ start: Date, hours: Double = 1, cal calID: String = "W",
            allDay: Bool = false, location: String? = nil, recurring: Bool = false, daily: Bool = false) -> CalEvent {
        CalEvent(id: id, title: title, start: start, end: start.addingTimeInterval(hours * 3600),
                 isAllDay: allDay, calendarID: calID, location: location, isRecurring: recurring, isDailyRoutine: daily)
    }

    func allDay(_ id: String, _ title: String, _ start: Date, days: Int, cal calID: String = "T") -> CalEvent {
        // EventKit 的全天事件結束在最後一天的 23:59:59
        CalEvent(id: id, title: title, start: start, end: start.addingTimeInterval(Double(days) * 86400 - 1),
                 isAllDay: true, calendarID: calID)
    }

    func builder(today: Date) -> LayoutBuilder {
        LayoutBuilder(calendar: cal, today: today, settings: settings)
    }

    // MARK: 類別

    func testCategoryFromCalendarAndFallback() {
        XCTAssertEqual(Classifier.categoryID(for: ev("1", "週會", date(2026, 11, 16, 10)), settings: settings), "work")
        XCTAssertEqual(Classifier.categoryID(for: ev("2", "吃飯", date(2026, 11, 16, 10), cal: "?"), settings: settings), "life")
    }

    func testKeywordRuleOverridesCalendar() {
        settings.keywordRules = [KeywordRule(keyword: "回診", categoryID: "life")]
        XCTAssertEqual(Classifier.categoryID(for: ev("1", "牙科回診", date(2026, 11, 16, 10)), settings: settings), "life")
    }

    func testRuleWithUnknownCategoryIsIgnored() {
        settings.keywordRules = [KeywordRule(keyword: "回診", categoryID: "gone")]
        XCTAssertEqual(Classifier.categoryID(for: ev("1", "牙科回診", date(2026, 11, 16, 10)), settings: settings), "work")
    }

    // MARK: 格內文字

    func testCellLabel() {
        XCTAssertEqual(CellText.label(title: "領包裹", shortName: nil), "領包裹")
        XCTAssertEqual(CellText.label(title: "填寫入境資料", shortName: nil), "填寫入境資料")
        XCTAssertEqual(CellText.label(title: "填寫入境資料表格", shortName: nil), "填寫入境資料")
        XCTAssertEqual(CellText.label(title: "填寫入境資料表格", shortName: "入境表"), "入境表")
        XCTAssertEqual(CellText.label(title: "Weekly sync with team", shortName: nil), "Weekly sync")
        // 短名本身太長也要截
        XCTAssertEqual(CellText.label(title: "填寫入境資料表格", shortName: "一二三四五六七八"), "一二三四五六")
    }

    // MARK: 主事件

    func classified(_ e: CalEvent) -> ClassifiedEvent {
        ClassifiedEvent(event: e, categoryID: Classifier.categoryID(for: e, settings: settings),
                        label: e.title, isPinned: settings.pinned.contains(e.seriesID))
    }

    func testHeadPrefersPinned() {
        settings.pinned = ["c"]
        let d = date(2026, 11, 16)
        let evs = [ev("a", "晨會", d.addingTimeInterval(9 * 3600)),
                   ev("b", "回診", d.addingTimeInterval(10 * 3600), cal: "M"),
                   ev("c", "錄影", d.addingTimeInterval(14 * 3600))].map(classified)
        XCTAssertEqual(HeadPicker.pick(evs, settings: settings)?.id, "c")
    }

    func testHeadPrefersPriorityCategoryOrLocation() {
        let d = date(2026, 11, 16)
        let a = [ev("a", "晨會", d.addingTimeInterval(9 * 3600)),
                 ev("b", "回診", d.addingTimeInterval(15 * 3600), cal: "M")].map(classified)
        XCTAssertEqual(HeadPicker.pick(a, settings: settings)?.id, "b")
        let b = [ev("a", "晨會", d.addingTimeInterval(9 * 3600)),
                 ev("b", "提案", d.addingTimeInterval(15 * 3600), location: "信義區")].map(classified)
        XCTAssertEqual(HeadPicker.pick(b, settings: settings)?.id, "b")
    }

    func testHeadPrefersOneOffThenEarliest() {
        let d = date(2026, 11, 16)
        let a = [ev("a", "晨會", d.addingTimeInterval(9 * 3600), recurring: true),
                 ev("b", "交稿", d.addingTimeInterval(15 * 3600))].map(classified)
        XCTAssertEqual(HeadPicker.pick(a, settings: settings)?.id, "b")
        let b = [ev("a", "寫腳本", d.addingTimeInterval(10 * 3600)),
                 ev("b", "剪片", d.addingTimeInterval(9 * 3600))].map(classified)
        XCTAssertEqual(HeadPicker.pick(b, settings: settings)?.id, "b")
        XCTAssertNil(HeadPicker.pick([], settings: settings))
    }

    // MARK: 週版面

    func testWeeksCollapseAndPast() {
        // 2026/11/14 是週六
        let today = date(2026, 11, 14)
        let events = [ev("a", "領包裹", date(2026, 11, 3, 10), cal: "E"),
                      ev("b", "週會", date(2026, 11, 16, 10)),
                      ev("c", "交稿", date(2026, 11, 16, 15))]
        let b = builder(today: today)
        let weeks = b.weeks(from: date(2026, 11, 1), to: date(2026, 11, 30), events: events)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks[0].days[0].date, date(2026, 11, 1))
        // 第一週有事但整週過去 → 收合
        XCTAssertTrue(weeks[0].isAllPast)
        XCTAssertTrue(weeks[0].isCollapsed)
        // 今天所在的週沒事 → 收合，但不算過去
        XCTAssertFalse(weeks[1].isAllPast)
        XCTAssertTrue(weeks[1].isCollapsed)
        XCTAssertTrue(weeks[1].days[6].isToday)
        XCTAssertTrue(weeks[1].days[5].isPast)
        // 有事的週展開
        XCTAssertFalse(weeks[2].isCollapsed)
        let mon = weeks[2].days[1]
        XCTAssertEqual(mon.events.map(\.id), ["b", "c"])
        XCTAssertEqual(mon.head?.id, "b")
        XCTAssertEqual(mon.rest.map(\.id), ["c"])
        XCTAssertTrue(weeks[3].isCollapsed)
    }

    func testWeekStartsOnMonday() {
        cal.firstWeekday = 2
        let weeks = builder(today: date(2026, 11, 14)).weeks(from: date(2026, 11, 1), to: date(2026, 11, 1), events: [])
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].days[0].date, date(2026, 10, 26))
        XCTAssertEqual(weeks[0].days[6].date, date(2026, 11, 1))
    }

    func testMultiDayBandAcrossWeeks() {
        // 11/27（五）到 12/4（五），共 8 天
        let trip = allDay("t", "去旅行", date(2026, 11, 27), days: 8)
        let b = builder(today: date(2026, 11, 14))
        let weeks = b.weeks(from: date(2026, 11, 22), to: date(2026, 12, 5), events: [trip])
        XCTAssertEqual(weeks.count, 2)
        let s0 = weeks[0].segments[0], s1 = weeks[1].segments[0]
        XCTAssertEqual([s0.startCol, s0.endCol], [5, 6])
        XCTAssertTrue(s0.startsHere)
        XCTAssertFalse(s0.endsHere)
        XCTAssertEqual([s1.startCol, s1.endCol], [0, 5])
        XCTAssertFalse(s1.startsHere)
        XCTAssertTrue(s1.endsHere)
        XCTAssertEqual(s0.band.totalDays, 8)
        XCTAssertFalse(weeks[0].isCollapsed)
        // 跨日事件不佔主事件
        XCTAssertNil(weeks[0].days[5].head)
        XCTAssertEqual(weeks[0].days[5].bands.count, 1)
        XCTAssertEqual(weeks[1].days[6].bands.count, 0)

        let rows = b.detailRows(for: weeks[1].days[0])
        XCTAssertEqual(rows.first?.kind, .band(dayNumber: 3, totalDays: 8))
        XCTAssertEqual(rows.first?.timeText, "全天")
    }

    func testOvernightTimedEventIsNotABand() {
        let party = ev("p", "跨年", date(2026, 12, 31, 23), hours: 2)
        let weeks = builder(today: date(2026, 11, 14)).weeks(from: date(2026, 12, 31), to: date(2026, 12, 31), events: [party])
        XCTAssertTrue(weeks[0].segments.isEmpty)
        XCTAssertEqual(weeks[0].days[4].events.map(\.id), ["p"])
    }

    func testSingleAllDayEventIsNormalEvent() {
        let e = allDay("a", "繳稅", date(2026, 11, 18), days: 1, cal: "E")
        let b = builder(today: date(2026, 11, 14))
        let weeks = b.weeks(from: date(2026, 11, 18), to: date(2026, 11, 18), events: [e])
        XCTAssertTrue(weeks[0].segments.isEmpty)
        XCTAssertEqual(weeks[0].days[3].head?.id, "a")
        XCTAssertEqual(b.detailRows(for: weeks[0].days[3]).first?.timeText, "全天")
    }

    func testOverlappingBandsGetLanes() {
        let a = allDay("a", "出差", date(2026, 11, 16), days: 5)
        let b2 = allDay("b", "展覽", date(2026, 11, 17), days: 2)
        let c = allDay("c", "連假", date(2026, 11, 18), days: 3)
        let d = allDay("d", "之後", date(2026, 11, 19), days: 2)
        let weeks = builder(today: date(2026, 11, 14)).weeks(from: date(2026, 11, 16), to: date(2026, 11, 16), events: [d, c, b2, a])
        let lanes = Dictionary(uniqueKeysWithValues: weeks[0].segments.map { ($0.band.id, $0.band.lane) })
        XCTAssertEqual(lanes["a"], 0)
        XCTAssertEqual(lanes["b"], 1)
        XCTAssertEqual(lanes["c"], 2)
        // 展覽 11/18 結束，11/19 開始的可以接回第 1 條
        XCTAssertEqual(lanes["d"], 1)
    }

    func testHeadModeWritesOnlyFirstBand() {
        // 彈性週：前兩條寫字，第三條起細線
        XCTAssertFalse(BandStyle.isThin(lane: 0, mode: .flex))
        XCTAssertFalse(BandStyle.isThin(lane: 1, mode: .flex))
        XCTAssertFalse(BandStyle.isThin(lane: 2, mode: .flex))
        XCTAssertFalse(BandStyle.isThin(lane: 5, mode: .flex))
        // 主事件：只有第一條寫字
        XCTAssertFalse(BandStyle.isThin(lane: 0, mode: .head))
        XCTAssertTrue(BandStyle.isThin(lane: 1, mode: .head))
        XCTAssertTrue(BandStyle.isThin(lane: 2, mode: .head))
    }

    func testHolidayRoutineAndHiddenCalendars() {
        settings.hiddenCalendarIDs = ["X"]
        let events = [allDay("h", "行憲紀念日", date(2026, 12, 25), days: 1, cal: "H"),
                      ev("r", "吃藥", date(2026, 12, 25, 8), cal: "M", recurring: true, daily: true),
                      ev("x", "別人的行程", date(2026, 12, 25, 9), cal: "X")]
        let b = builder(today: date(2026, 11, 14))
        let weeks = b.weeks(from: date(2026, 12, 25), to: date(2026, 12, 25), events: events)
        let day = weeks[0].days[5]
        XCTAssertEqual(day.holidays, ["行憲紀念日"])
        XCTAssertTrue(day.events.isEmpty)
        XCTAssertNil(day.head)
        XCTAssertEqual(day.routines.map(\.id), ["r"])
        // 只有節日和例行事件的週不展開
        XCTAssertTrue(weeks[0].isCollapsed)
        XCTAssertEqual(b.detailRows(for: day).map(\.kind), [.routine])
    }

    func testPinnedAndShortNameApplied() {
        settings.pinned = ["s2"]
        settings.shortNames = ["s2": "入境表"]
        var e2 = ev("b", "填寫入境資料表格", date(2026, 11, 16, 15))
        e2.seriesID = "s2"
        let weeks = builder(today: date(2026, 11, 14)).weeks(
            from: date(2026, 11, 16), to: date(2026, 11, 16),
            events: [ev("a", "回診", date(2026, 11, 16, 9), cal: "M"), e2])
        let day = weeks[0].days[1]
        XCTAssertEqual(day.head?.id, "b")
        XCTAssertEqual(day.head?.label, "入境表")
    }

    func testHeadModeWritesOnlyOneThingPerDay() {
        // 11/17 到 11/18 有一條跨日的；17 號還有兩件單日的；19 號沒有色帶，有兩件單日的
        let events = [allDay("trip", "出差", date(2026, 11, 17), days: 2),
                      ev("a", "打籃球", date(2026, 11, 17, 19)),
                      ev("b", "牙醫", date(2026, 11, 17, 9), cal: "M"),
                      ev("c", "週會", date(2026, 11, 19, 10)),
                      ev("d", "聚餐", date(2026, 11, 19, 18))]
        let weeks = builder(today: date(2026, 11, 14)).weeks(from: date(2026, 11, 17), to: date(2026, 11, 17), events: events)
        let covered = weeks[0].days[2]
        // 上面有寫字的色帶：這一格不再寫字，單日的兩件都是小色塊
        XCTAssertTrue(covered.hasWrittenBand)
        XCTAssertNil(covered.headChip)
        XCTAssertEqual(Set(covered.headPips.map(\.id)), ["a", "b"])
        // 主事件本身沒有變，點開那一天的時間表照舊
        XCTAssertNotNil(covered.head)
        // 沒有色帶的日子照舊：一件寫字，其餘小色塊
        let plain = weeks[0].days[4]
        XCTAssertFalse(plain.hasWrittenBand)
        XCTAssertEqual(plain.headChip?.id, plain.head?.id)
        XCTAssertEqual(plain.headPips.map(\.id), plain.rest.map(\.id))
        XCTAssertEqual(plain.headPips.count, 1)
    }

    func testHeadModeThinBandDoesNotTakeTheWrittenSpot() {
        // 兩條跨日的重疊：第二條縮成細線。只被細線蓋到的日子，單日的那一件照樣寫字
        let events = [allDay("long", "去韓國", date(2026, 11, 16), days: 2),
                      allDay("short", "特賣", date(2026, 11, 17), days: 3),
                      ev("a", "牙醫", date(2026, 11, 19, 9), cal: "M")]
        let weeks = builder(today: date(2026, 11, 14)).weeks(from: date(2026, 11, 17), to: date(2026, 11, 17), events: events)
        let day = weeks[0].days[4]
        XCTAssertEqual(day.bands.map(\.lane), [1])
        XCTAssertFalse(day.hasWrittenBand)
        XCTAssertEqual(day.headChip?.id, "a")
        XCTAssertTrue(day.headPips.isEmpty)
    }

    // MARK: 週條與清單

    func testStripItems() {
        let trip = allDay("t", "去旅行", date(2026, 11, 20), days: 2)
        let events = [ev("a", "週會", date(2026, 11, 16, 10)), trip]
        let b = builder(today: date(2026, 11, 14))
        let week = b.weeks(from: date(2026, 11, 16), to: date(2026, 11, 16), events: events)[0]
        let items = b.stripItems(for: week)
        XCTAssertEqual(items.count, 6)
        guard case .narrow = items[0], case .card(let d) = items[1], case .trip(let seg) = items[5] else {
            return XCTFail("週條項目種類不對：\(items)")
        }
        XCTAssertEqual(d.date, date(2026, 11, 16))
        XCTAssertEqual(seg.span, 2)
    }

    func testStripCompactWhenFourBusyDays() {
        let events = (16...19).map { ev("e\($0)", "會議", date(2026, 11, $0, 10)) }
        let b = builder(today: date(2026, 11, 14))
        let week = b.weeks(from: date(2026, 11, 16), to: date(2026, 11, 16), events: events)[0]
        let compactCount = b.stripItems(for: week).filter { if case .compact = $0 { return true } else { return false } }.count
        XCTAssertEqual(compactCount, 4)
    }

    func testUpcoming() {
        let events = [ev("old", "過去", date(2026, 11, 10, 10)),
                      ev("a", "今天的事", date(2026, 11, 14, 10)),
                      ev("b", "週會", date(2026, 11, 16, 10)),
                      allDay("t", "去旅行", date(2026, 11, 27), days: 8),
                      allDay("on", "進修", date(2026, 11, 12), days: 5)]
        let b = builder(today: date(2026, 11, 14))
        let weeks = b.weeks(from: date(2026, 11, 1), to: date(2026, 12, 31), events: events)
        let cards = b.upcoming(in: weeks)
        XCTAssertEqual(cards.map(\.awayText), ["進行中", "今天", "2 天後", "13 天後"])
        XCTAssertEqual(cards.count, 4)
    }

    // MARK: 時間軸

    func testTimeBlocksSideBySideWhenOverlapping() {
        let d = date(2026, 11, 16)
        let events = [ev("a", "錄影", d.addingTimeInterval(14 * 3600), hours: 2),
                      ev("b", "牙醫", d.addingTimeInterval(14.5 * 3600), hours: 1, cal: "M"),
                      ev("c", "取件", d.addingTimeInterval(19 * 3600), hours: 0.5, cal: "E"),
                      ev("r", "吃藥", d.addingTimeInterval(8 * 3600), hours: 0.25, cal: "M", recurring: true, daily: true),
                      allDay("x", "繳稅", d, days: 1, cal: "E")]
        let b = builder(today: date(2026, 11, 14))
        let day = b.weeks(from: d, to: d, events: events)[0].days[1]
        let blocks = Dictionary(uniqueKeysWithValues: b.timeBlocks(for: day).map { ($0.id, $0) })
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual([blocks["a"]!.startMinute, blocks["a"]!.endMinute], [840, 960])
        XCTAssertEqual([blocks["a"]!.column, blocks["a"]!.columnCount], [0, 2])
        XCTAssertEqual([blocks["b"]!.column, blocks["b"]!.columnCount], [1, 2])
        XCTAssertEqual([blocks["c"]!.column, blocks["c"]!.columnCount], [0, 1])
        // 15 分鐘的例行事件也排進時間軸，畫成最少 30 分鐘高
        XCTAssertEqual([blocks["r"]!.startMinute, blocks["r"]!.endMinute], [480, 510])
        // 全天行程不進時間軸
        XCTAssertNil(blocks["x"])
        XCTAssertEqual(b.allDayEvents(for: day).map(\.id), ["x"])
        XCTAssertEqual(b.endTimeText(events[0]), "16:00")
    }

    func testTimeBlocksReuseColumnAndClipAtMidnight() {
        let d = date(2026, 11, 16)
        let events = [ev("a", "長會議", d.addingTimeInterval(9 * 3600), hours: 3),
                      ev("b", "插進來", d.addingTimeInterval(9.5 * 3600), hours: 1),
                      ev("c", "再插", d.addingTimeInterval(11 * 3600), hours: 1),
                      ev("late", "跨年", d.addingTimeInterval(23.75 * 3600), hours: 2)]
        let b = builder(today: date(2026, 11, 14))
        let day = b.weeks(from: d, to: d, events: events)[0].days[1]
        let blocks = Dictionary(uniqueKeysWithValues: b.timeBlocks(for: day).map { ($0.id, $0) })
        // b 結束後，c 接回第 1 欄；三件同一群，都分成兩欄
        XCTAssertEqual([blocks["a"]!.column, blocks["b"]!.column, blocks["c"]!.column], [0, 1, 1])
        XCTAssertEqual(blocks["c"]!.columnCount, 2)
        // 跨過午夜的只畫到 24:00，而且至少 30 分鐘高
        XCTAssertEqual([blocks["late"]!.startMinute, blocks["late"]!.endMinute], [1410, 1440])
        XCTAssertEqual(blocks["late"]!.columnCount, 1)
    }

    func testAgendaDays() {
        let events = [ev("old", "過去", date(2026, 11, 10, 10)),
                      ev("b", "週會", date(2026, 11, 16, 10)),
                      allDay("t", "去旅行", date(2026, 11, 27), days: 2)]
        let b = builder(today: date(2026, 11, 14))
        let weeks = b.weeks(from: date(2026, 11, 1), to: date(2026, 11, 30), events: events)
        let days = b.agendaDays(in: weeks).map(\.date)
        // 今天沒事也列；過去的不列；跨日行程每一天都列
        XCTAssertEqual(days, [date(2026, 11, 14), date(2026, 11, 16), date(2026, 11, 27), date(2026, 11, 28)])
    }

    func testViewKindDecodeDefault() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: #"{"mode":"C"}"#.data(using: .utf8)!)
        XCTAssertEqual(s.view, .month)
        XCTAssertEqual(ViewKind.week.dayCount, 7)
        XCTAssertNil(ViewKind.agenda.dayCount)
    }

    // MARK: 農曆與節氣

    func testSolarTerms() {
        XCTAssertEqual(Lunar.solarTerm(year: 2026, month: 2, day: 4), "立春")
        XCTAssertEqual(Lunar.solarTerm(year: 2026, month: 2, day: 18), "雨水")
        XCTAssertEqual(Lunar.solarTerm(year: 2026, month: 4, day: 5), "清明")
        XCTAssertEqual(Lunar.solarTerm(year: 2026, month: 12, day: 22), "冬至")
        XCTAssertEqual(Lunar.solarTerm(year: 2025, month: 12, day: 21), "冬至")
        XCTAssertEqual(Lunar.solarTerm(year: 2027, month: 1, day: 5), "小寒")
        XCTAssertNil(Lunar.solarTerm(year: 2026, month: 11, day: 14))
        XCTAssertNil(Lunar.solarTerm(year: 1999, month: 2, day: 4))
        XCTAssertEqual(Lunar.solarTerm(for: date(2026, 11, 7), calendar: cal), "立冬")
    }

    func testLunarDay() {
        let tz = TimeZone(identifier: "Asia/Taipei")!
        // 2026/2/17 是農曆正月初一
        let newYear = Lunar.lunarDay(for: date(2026, 2, 17, 12), timeZone: tz)
        XCTAssertEqual(newYear, Lunar.LunarDay(month: 1, day: 1, isLeapMonth: false))
        XCTAssertEqual(newYear.shortText, "正月")
        // 2026/9/25 是中秋（八月十五）
        let moon = Lunar.lunarDay(for: date(2026, 9, 25, 12), timeZone: tz)
        XCTAssertEqual(moon.shortText, "十五")
        XCTAssertEqual(moon.fullText, "農曆八月十五")
        XCTAssertEqual(Lunar.LunarDay(month: 6, day: 1, isLeapMonth: true).shortText, "閏六月")
        XCTAssertEqual(Lunar.LunarDay(month: 0, day: 0, isLeapMonth: false).shortText, "")
    }

    // MARK: 設定存檔

    func testSettingsDecodeFillsMissingFields() throws {
        let json = #"{"mode":"C","pinned":["a"]}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.mode, .strips)
        XCTAssertEqual(s.pinned, ["a"])
        XCTAssertEqual(s.categories.count, 4)
        XCTAssertTrue(s.showLunar)
        XCTAssertFalse(s.weatherEnabled)
        XCTAssertNil(s.weatherCityID)
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round, s)
    }

    func testThemeSettingDefaultsAndRoundTrips() throws {
        // 舊版存的設定沒有主題這一欄，讀回來要是預設那款
        let old = #"{"mode":"C"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).themeID, AppSettings.defaultThemeID)

        var s = AppSettings()
        XCTAssertEqual(s.themeID, "sage")
        s.themeID = "hongdou"
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.themeID, "hongdou")
        XCTAssertEqual(round, s)
    }

    // MARK: 主題的付費判斷

    func testFreeThemeAlwaysUsable() {
        XCTAssertTrue(ThemeAccess.canApply("sage", isUnlocked: false))
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "sage", previewing: nil, isUnlocked: false), "sage")
    }

    func testPaidThemeLockedWithoutPurchase() {
        XCTAssertFalse(ThemeAccess.canApply("hongdou", isUnlocked: false))
        // 設定裡選了付費款但沒買（退款、還沒驗到）：畫面用預設款
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "hongdou", previewing: nil, isUnlocked: false), "sage")
        // 不認得的名字也當成付費款，沒買就是預設款
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "whatever", previewing: nil, isUnlocked: false), "sage")
    }

    func testPaidThemeUsableAfterPurchase() {
        XCTAssertTrue(ThemeAccess.canApply("hongdou", isUnlocked: true))
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "hongdou", previewing: nil, isUnlocked: true), "hongdou")
    }

    func testPreviewShowsOnlyWhilePreviewing() {
        // 試看中：沒買也看得到
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "sage", previewing: "shuimo", isUnlocked: false), "shuimo")
        // 試看結束：回到原本那款
        XCTAssertEqual(ThemeAccess.effectiveThemeID(selected: "sage", previewing: nil, isUnlocked: false), "sage")
    }

    func testCountdownLimitWithoutPurchase() {
        XCTAssertTrue(FullVersionAccess.canAddCountdown(currentCount: 0, isUnlocked: false))
        XCTAssertTrue(FullVersionAccess.canAddCountdown(currentCount: 2, isUnlocked: false))
        // 第四個起要完整版
        XCTAssertFalse(FullVersionAccess.canAddCountdown(currentCount: 3, isUnlocked: false))
        XCTAssertTrue(FullVersionAccess.canAddCountdown(currentCount: 3, isUnlocked: true))
        XCTAssertTrue(FullVersionAccess.canAddCountdown(currentCount: 50, isUnlocked: true))
    }

    func testCountdownsAfterRefundShowFirstThree() {
        let ids = ["a", "b", "c", "d", "e"]
        // 退款或還沒驗到：只顯示最早加入的三個，順序不變
        XCTAssertEqual(FullVersionAccess.visibleCountdowns(ids, isUnlocked: false), ["a", "b", "c"])
        XCTAssertEqual(FullVersionAccess.visibleCountdowns(ids, isUnlocked: true), ids)
        XCTAssertEqual(FullVersionAccess.visibleCountdowns(["a"], isUnlocked: false), ["a"])
    }

    func testDisplayModeLock() {
        XCTAssertTrue(FullVersionAccess.canApply(.flex, isUnlocked: false))
        XCTAssertTrue(FullVersionAccess.canApply(.list, isUnlocked: false))
        XCTAssertFalse(FullVersionAccess.canApply(.strips, isUnlocked: false))
        XCTAssertFalse(FullVersionAccess.canApply(.head, isUnlocked: false))
        XCTAssertTrue(FullVersionAccess.canApply(.head, isUnlocked: true))
        // 選了付費樣式但沒買（退款、還沒驗到）：畫面退回彈性週
        XCTAssertEqual(FullVersionAccess.effectiveMode(selected: .strips, previewing: nil, isUnlocked: false), .flex)
        XCTAssertEqual(FullVersionAccess.effectiveMode(selected: .strips, previewing: nil, isUnlocked: true), .strips)
        XCTAssertEqual(FullVersionAccess.effectiveMode(selected: .list, previewing: nil, isUnlocked: false), .list)
        // 試看中：沒買也看得到；試看結束回到原本那種
        XCTAssertEqual(FullVersionAccess.effectiveMode(selected: .flex, previewing: .head, isUnlocked: false), .head)
        XCTAssertEqual(FullVersionAccess.effectiveMode(selected: .flex, previewing: nil, isUnlocked: false), .flex)
    }

    func testCustomCategoryColorNeedsPurchase() {
        XCTAssertFalse(FullVersionAccess.canUseCustomCategoryColor(isUnlocked: false))
        XCTAssertTrue(FullVersionAccess.canUseCustomCategoryColor(isUnlocked: true))
        XCTAssertEqual(FullVersionAccess.presetCategoryHexes.count, 4)
    }

    func testUsesPaidContent() {
        XCTAssertFalse(FullVersionAccess.usesPaidContent(AppSettings()))
        XCTAssertTrue(FullVersionAccess.usesPaidContent(AppSettings(themeID: "hongdou")))
        XCTAssertTrue(FullVersionAccess.usesPaidContent(AppSettings(mode: .head)))
        XCTAssertFalse(FullVersionAccess.usesPaidContent(AppSettings(countdowns: ["a", "b", "c"])))
        XCTAssertTrue(FullVersionAccess.usesPaidContent(AppSettings(countdowns: ["a", "b", "c", "d"])))
    }

    func testWeatherCitySettingRoundTrips() throws {
        var s = AppSettings()
        s.weatherEnabled = true
        s.weatherCityID = "taipei"
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round, s)
        XCTAssertEqual(WeatherCity.find(round.weatherCityID)?.name, "臺北市")
    }

    // MARK: 行事曆順序

    func testCalendarOrderPutsUnknownLastAndKeepsTheirOrder() {
        XCTAssertEqual(CalendarOrder.sorted(["A", "B", "C", "D"], by: ["C", "A"]), ["C", "A", "B", "D"])
        XCTAssertEqual(CalendarOrder.sorted(["A", "B"], by: []), ["A", "B"])
        XCTAssertEqual(CalendarOrder.sorted(["A"], by: ["不在手機上的", "A"]), ["A"])
    }

    func testSameStartFollowsCalendarOrder() {
        let day = date(2026, 11, 18)
        let events = [
            ev("a", "工作的事", date(2026, 11, 18, 10), cal: "W"),
            ev("b", "辦事的事", date(2026, 11, 18, 10), cal: "E"),
            ev("c", "更早的事", date(2026, 11, 18, 9), cal: "W")
        ]
        // 沒排過：開始時間一樣的照識別碼
        var week = builder(today: day).weeks(from: day, to: day, events: events)[0]
        XCTAssertEqual(week.days.first { $0.date == day }?.events.map(\.id), ["c", "a", "b"])
        // 把辦事那本排到前面：同一時間的兩件對調，比較早的那件還是最前面
        settings.calendarOrder = ["E", "W"]
        week = builder(today: day).weeks(from: day, to: day, events: events)[0]
        XCTAssertEqual(week.days.first { $0.date == day }?.events.map(\.id), ["c", "b", "a"])
    }

    func testCalendarOrderRoundTripsAndOldSettingsStillLoad() throws {
        var s = AppSettings()
        s.calendarOrder = ["X", "Y"]
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.calendarOrder, ["X", "Y"])
        let old = #"{"mode":"A"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).calendarOrder, [])
    }

    // MARK: 時區

    func testEffectiveTimeZone() {
        let taipei = TimeZone(identifier: "Asia/Taipei")!
        XCTAssertEqual(AppSettings().effectiveTimeZone(device: taipei), taipei)
        // 開關還開著：就算選過別的時區也照手機的
        XCTAssertEqual(AppSettings(usesDeviceTimeZone: true, timeZoneID: "Asia/Tokyo").effectiveTimeZone(device: taipei), taipei)
        XCTAssertEqual(
            AppSettings(usesDeviceTimeZone: false, timeZoneID: "Asia/Tokyo").effectiveTimeZone(device: taipei).identifier,
            "Asia/Tokyo"
        )
        // 關了但還沒選、或存的值不認得：照手機的
        XCTAssertEqual(AppSettings(usesDeviceTimeZone: false).effectiveTimeZone(device: taipei), taipei)
        XCTAssertEqual(AppSettings(usesDeviceTimeZone: false, timeZoneID: "不存在/哪裡").effectiveTimeZone(device: taipei), taipei)
    }

    func testTimeZoneSettingRoundTripsAndOldSettingsStillLoad() throws {
        let s = AppSettings(usesDeviceTimeZone: false, timeZoneID: "Asia/Tokyo")
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round, s)
        let old = try JSONDecoder().decode(AppSettings.self, from: #"{"mode":"A"}"#.data(using: .utf8)!)
        XCTAssertTrue(old.usesDeviceTimeZone)
        XCTAssertNil(old.timeZoneID)
    }

    func testAllDayEventKeepsItsDateInAnotherTimeZone() {
        let taipei = TimeZone(identifier: "Asia/Taipei")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var tokyoCal = Calendar(identifier: .gregorian)
        tokyoCal.timeZone = tokyo
        // 手機在台北，11/18 的全天行程：台北的 00:00 到 23:59:59
        let start = date(2026, 11, 18)
        let end = start.addingTimeInterval(86400 - 1)
        let movedStart = FloatingTime.moved(start, from: taipei, to: tokyo)
        let movedEnd = FloatingTime.moved(end, from: taipei, to: tokyo)
        XCTAssertEqual(tokyoCal.component(.day, from: movedStart), 18)
        XCTAssertEqual(tokyoCal.component(.hour, from: movedStart), 0)
        XCTAssertEqual(tokyoCal.component(.day, from: movedEnd), 18)
        XCTAssertEqual(tokyoCal.component(.hour, from: movedEnd), 23)
        // 同一個時區：不動
        XCTAssertEqual(FloatingTime.moved(start, from: taipei, to: taipei), start)
    }

    func testWeatherCityList() {
        XCTAssertEqual(WeatherCity.all.count, 22)
        XCTAssertEqual(Set(WeatherCity.all.map(\.id)).count, 22)
        XCTAssertNil(WeatherCity.find(nil))
        XCTAssertNil(WeatherCity.find("不存在"))
    }

    // MARK: 自己的新增行程畫面

    func draft(_ day: Date, start: Int = 16 * 60, duration: Int = 60) -> NewEventDraft {
        NewEventDraft(title: "開會", day: day, startMinutes: start, durationMinutes: duration)
    }

    func testNewEventDefaultStart() {
        let today = date(2026, 11, 16)
        // 今天是下一個整點，最晚 23:00；其他天是早上 9 點
        XCTAssertEqual(NewEventRules.defaultStartMinutes(day: today, now: date(2026, 11, 16, 15, 44), calendar: cal), 16 * 60)
        XCTAssertEqual(NewEventRules.defaultStartMinutes(day: today, now: date(2026, 11, 16, 23, 30), calendar: cal), 23 * 60)
        XCTAssertEqual(NewEventRules.defaultStartMinutes(day: date(2026, 11, 20), now: date(2026, 11, 16, 15, 44), calendar: cal), 9 * 60)
        let d = NewEventRules.initialDraft(day: date(2026, 11, 16, 13, 5), now: date(2026, 11, 16, 15, 44), calendar: cal)
        XCTAssertEqual(d.day, today)
        XCTAssertEqual(d.durationMinutes, 60)
        XCTAssertEqual(d.kind, .timed)
    }

    func testQuickDayIndex() {
        let today = date(2026, 11, 16, 15)
        XCTAssertEqual(NewEventRules.quickDayIndex(of: date(2026, 11, 16), today: today, calendar: cal), 0)
        XCTAssertEqual(NewEventRules.quickDayIndex(of: date(2026, 11, 18), today: today, calendar: cal), 2)
        XCTAssertNil(NewEventRules.quickDayIndex(of: date(2026, 11, 19), today: today, calendar: cal))
        XCTAssertNil(NewEventRules.quickDayIndex(of: date(2026, 11, 15), today: today, calendar: cal))
    }

    func testSettingStartKeepsLengthAndSettingEndChangesIt() {
        let base = draft(date(2026, 11, 16))
        let moved = NewEventRules.settingStart(10 * 60 + 30, in: base)
        XCTAssertEqual(moved.durationMinutes, 60)
        XCTAssertEqual(moved.endMinutes, 11 * 60 + 30)
        let longer = NewEventRules.settingEnd(12 * 60, in: moved)
        XCTAssertEqual(longer.durationMinutes, 90)
        // 結束比開始早：當成隔天
        let overnight = NewEventRules.settingEnd(1 * 60, in: draft(date(2026, 11, 16), start: 23 * 60))
        XCTAssertEqual(overnight.durationMinutes, 120)
        XCTAssertTrue(overnight.endsNextDay)
        XCTAssertEqual(overnight.endMinutes, 60)
    }

    func testResolveTimedAllDayAndMultiDay() {
        let day = date(2026, 11, 16)
        let timed = NewEventRules.resolve(draft(day), calendar: cal)
        XCTAssertEqual(timed, ResolvedEventTime(start: date(2026, 11, 16, 16), end: date(2026, 11, 16, 17), isAllDay: false))
        var whole = draft(day)
        whole.kind = .allDay
        XCTAssertEqual(NewEventRules.resolve(whole, calendar: cal), ResolvedEventTime(start: day, end: day, isAllDay: true))
        var trip = draft(day)
        trip.kind = .multiDay
        XCTAssertNil(NewEventRules.resolve(trip, calendar: cal))
        trip.rangeStart = date(2026, 12, 5)
        XCTAssertEqual(NewEventRules.resolve(trip, calendar: cal)?.end, date(2026, 12, 5))
        trip.rangeEnd = date(2026, 12, 9)
        XCTAssertEqual(NewEventRules.resolve(trip, calendar: cal),
                       ResolvedEventTime(start: date(2026, 12, 5), end: date(2026, 12, 9), isAllDay: true))
    }

    func testTappingRangeDays() {
        var d = draft(date(2026, 11, 16))
        d.kind = .multiDay
        XCTAssertEqual(NewEventRules.rangeDayCount(d, calendar: cal), 0)
        d = NewEventRules.tappingRangeDay(date(2026, 12, 9), in: d, calendar: cal)
        XCTAssertEqual(d.rangeStart, date(2026, 12, 9))
        XCTAssertEqual(NewEventRules.rangeDayCount(d, calendar: cal), 1)
        // 第二下點在開始之前：改當開始，還要再點結束
        d = NewEventRules.tappingRangeDay(date(2026, 12, 5), in: d, calendar: cal)
        XCTAssertEqual(d.rangeStart, date(2026, 12, 5))
        XCTAssertNil(d.rangeEnd)
        d = NewEventRules.tappingRangeDay(date(2026, 12, 9), in: d, calendar: cal)
        XCTAssertEqual(d.rangeEnd, date(2026, 12, 9))
        XCTAssertEqual(NewEventRules.rangeDayCount(d, calendar: cal), 5)
        // 兩個都有了再點：重新選
        d = NewEventRules.tappingRangeDay(date(2026, 12, 20), in: d, calendar: cal)
        XCTAssertEqual(d.rangeStart, date(2026, 12, 20))
        XCTAssertNil(d.rangeEnd)
    }

    func testReminderFitsKindAndOffsets() {
        XCTAssertEqual(NewEventRules.reminder(.minutes30, fitting: .timed), .minutes30)
        XCTAssertNil(NewEventRules.reminder(.minutes30, fitting: .allDay))
        XCTAssertNil(NewEventRules.reminder(.sameDayMorning, fitting: .timed))
        XCTAssertEqual(NewEventRules.reminder(.dayBeforeMorning, fitting: .multiDay), .dayBeforeMorning)
        XCTAssertEqual(EventReminder.minutes30.offsetSeconds, -1800)
        XCTAssertEqual(EventReminder.sameDayMorning.offsetSeconds, 9 * 3600)
        XCTAssertEqual(EventReminder.dayBeforeMorning.offsetSeconds, -15 * 3600)
        XCTAssertEqual(Set(EventReminder.timedCases + EventReminder.allDayCases), Set(EventReminder.allCases))
    }

    func testPickCalendarForNewEvent() {
        XCTAssertEqual(NewEventRules.pickCalendar(lastUsed: "B", systemDefault: "A", available: ["A", "B"]), "B")
        // 上次那本被移除了：用 iPhone 的預設；預設也不在清單裡：用第一本
        XCTAssertEqual(NewEventRules.pickCalendar(lastUsed: "X", systemDefault: "A", available: ["B", "A"]), "A")
        XCTAssertEqual(NewEventRules.pickCalendar(lastUsed: nil, systemDefault: "X", available: ["B", "A"]), "B")
        XCTAssertNil(NewEventRules.pickCalendar(lastUsed: "B", systemDefault: "A", available: []))
    }

    func testMonthCellsAlignWeekdays() {
        // 2026 年 12 月 1 日是週二，一共 31 天
        let sundayFirst = NewEventRules.monthCells(month: date(2026, 12, 15), calendar: cal)
        XCTAssertEqual(sundayFirst.count, 2 + 31)
        XCTAssertNil(sundayFirst[1])
        XCTAssertEqual(sundayFirst[2], date(2026, 12, 1))
        XCTAssertEqual(sundayFirst[32], date(2026, 12, 31))
        var monday: Calendar = cal
        monday.firstWeekday = 2
        XCTAssertEqual(NewEventRules.monthCells(month: date(2026, 12, 15), calendar: monday).count, 1 + 31)
    }

    func testEventTexts() {
        XCTAssertEqual(EventText.day(date(2026, 11, 16), calendar: cal), "11月16日 週一")
        XCTAssertEqual(EventText.shortDay(date(2026, 11, 26), calendar: cal), "11/26 週四")
        XCTAssertEqual(EventText.year(date(2026, 11, 17), calendar: cal), "2026年")
        XCTAssertEqual(EventText.month(date(2026, 12, 5), calendar: cal), "2026年12月")
        XCTAssertEqual(EventText.time(0), "上午 12:00")
        XCTAssertEqual(EventText.time(12 * 60 + 5), "下午 12:05")
        XCTAssertEqual(EventText.timeRange(startMinutes: 16 * 60, durationMinutes: 60), "下午 4:00 – 5:00")
        XCTAssertEqual(EventText.timeRange(startMinutes: 11 * 60 + 30, durationMinutes: 60), "上午 11:30 – 下午 12:30")
        XCTAssertEqual(EventText.timeRange(startMinutes: 23 * 60, durationMinutes: 120), "下午 11:00 – 隔天上午 1:00")
        XCTAssertEqual(EventText.duration(90), "1 小時 30 分")
        XCTAssertEqual(EventRepeat.weekly.summary(from: date(2026, 11, 17), calendar: cal), "每週二")
        XCTAssertEqual(EventRepeat.monthly.summary(from: date(2026, 11, 17), calendar: cal), "每月 17 日")
    }

    func testShareText() {
        var d = draft(date(2026, 11, 16))
        d.title = "  跟廠商開會 "
        d.location = "信義區"
        XCTAssertEqual(EventText.shareText(d, calendar: cal), "跟廠商開會\n11月16日 週一 下午 4:00 – 5:00\n信義區")
        var trip = draft(date(2026, 11, 16))
        trip.title = "沖繩旅遊"
        trip.kind = .multiDay
        trip.rangeStart = date(2026, 12, 5)
        trip.rangeEnd = date(2026, 12, 9)
        XCTAssertEqual(EventText.shareText(trip, calendar: cal), "沖繩旅遊\n12月5日 週六 到 12月9日 週三（整日）")
    }

    func testGoogleLinkForTimedEvent() throws {
        var d = draft(date(2026, 11, 17), start: 19 * 60 + 30)
        d.title = "瑜珈課 + 伸展"
        d.repeats = .biweekly
        d.notes = "帶墊子"
        d.location = "信義區"
        let time = try XCTUnwrap(NewEventRules.resolve(d, calendar: cal))
        let url = try XCTUnwrap(GoogleCalendarLink.make(draft: d, time: time, calendar: cal))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(parts.host, "calendar.google.com")
        XCTAssertEqual(query["action"], "TEMPLATE")
        // 台北 19:30 是世界協調時間 11:30
        XCTAssertEqual(query["dates"], "20261117T113000Z/20261117T123000Z")
        XCTAssertEqual(query["text"], "瑜珈課 + 伸展")
        XCTAssertEqual(query["location"], "信義區")
        XCTAssertEqual(query["details"], "帶墊子")
        XCTAssertEqual(query["recur"], "RRULE:FREQ=WEEKLY;INTERVAL=2")
        // 加號要編碼，不然 Google 會讀成空白
        XCTAssertTrue(url.absoluteString.contains("%2B"))
    }

    func testGoogleLinkForMultiDayEventEndsTheDayAfter() throws {
        var d = draft(date(2026, 11, 16))
        d.title = "沖繩旅遊"
        d.kind = .multiDay
        d.rangeStart = date(2026, 12, 5)
        d.rangeEnd = date(2026, 12, 9)
        let time = try XCTUnwrap(NewEventRules.resolve(d, calendar: cal))
        let url = try XCTUnwrap(GoogleCalendarLink.make(draft: d, time: time, calendar: cal))
        XCTAssertTrue(url.absoluteString.contains("dates=20261205/20261210"))
        XCTAssertFalse(url.absoluteString.contains("recur="))
    }

    func testShareMessageEndsWithGoogleLink() {
        var d = draft(date(2026, 11, 18), start: 12 * 60)
        d.title = "上架行事曆app"
        let text = ShareMessage.text(d, calendar: cal)
        XCTAssertTrue(text.hasPrefix("上架行事曆app\n11月18日 週三 下午 12:00 – 1:00\n\n加到 Google 日曆：\nhttps://calendar.google.com/calendar/render?action=TEMPLATE"))
    }

    func testLastEventCalendarRoundTripsAndOldSettingsStillLoad() throws {
        var s = AppSettings()
        s.lastEventCalendarID = "CAL"
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.lastEventCalendarID, "CAL")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertNil(old.lastEventCalendarID)
    }

    // MARK: 每筆行程自己的類別、編輯既有的行程

    func testOwnCategoryBeatsKeywordAndCalendar() {
        var s = AppSettings(calendarCategory: ["CAL": "work"], keywordRules: [KeywordRule(keyword: "看牙", categoryID: "life")])
        let e = CalEvent(id: "E1|0", seriesID: "E1", title: "看牙", start: date(2026, 11, 17, 9), end: date(2026, 11, 17, 10), calendarID: "CAL")
        // 沒選過：關鍵字規則先，其次行事曆的預設
        XCTAssertEqual(Classifier.categoryID(for: e, settings: s), "life")
        s.eventCategory["E1"] = "rest"
        XCTAssertEqual(Classifier.categoryID(for: e, settings: s), "rest")
        // 同一本行事曆的另一筆不受影響
        let other = CalEvent(id: "E2|0", seriesID: "E2", title: "週會", start: date(2026, 11, 17, 9), end: date(2026, 11, 17, 10), calendarID: "CAL")
        XCTAssertEqual(Classifier.categoryID(for: other, settings: s), "work")
        // 選的那個類別被刪掉了，就回到原本的規則
        s.eventCategory["E1"] = "gone"
        XCTAssertEqual(Classifier.categoryID(for: e, settings: s), "life")
    }

    func testEventCategoryRoundTripsAndOldSettingsStillLoad() throws {
        var s = AppSettings()
        s.eventCategory["E1"] = "life"
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.eventCategory, ["E1": "life"])
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.eventCategory.isEmpty)
    }

    func testShownCategoryOnTheForm() {
        let s = AppSettings(calendarCategory: ["CAL": "work"], keywordRules: [KeywordRule(keyword: "看牙", categoryID: "life")])
        var d = NewEventDraft(title: "週會", day: date(2026, 11, 17), startMinutes: 540, calendarID: "CAL")
        XCTAssertEqual(NewEventRules.shownCategoryID(d, settings: s), "work")
        d.title = "看牙"
        XCTAssertEqual(NewEventRules.shownCategoryID(d, settings: s), "life")
        d.categoryID = "rest"
        XCTAssertEqual(NewEventRules.shownCategoryID(d, settings: s), "rest")
        d.categoryID = "gone"
        XCTAssertEqual(NewEventRules.shownCategoryID(d, settings: s), "life")
        d.calendarID = nil
        d.title = ""
        XCTAssertEqual(NewEventRules.shownCategoryID(d, settings: s), AppSettings.fallbackCategoryID)
    }

    func testDraftFromExistingEvent() {
        let timed = CalEvent(id: "T", title: "打籃球", start: date(2026, 11, 17, 6), end: date(2026, 11, 17, 7, 30), calendarID: "CAL", location: "河濱")
        let a = NewEventRules.draft(editing: timed, calendar: cal)
        XCTAssertEqual(a.kind, .timed)
        XCTAssertEqual(a.title, "打籃球")
        XCTAssertEqual(a.day, date(2026, 11, 17))
        XCTAssertEqual(a.startMinutes, 6 * 60)
        XCTAssertEqual(a.durationMinutes, 90)
        XCTAssertEqual(a.calendarID, "CAL")
        XCTAssertEqual(a.location, "河濱")
        // 轉成表單再算回起訖，要跟原本一樣
        let back = NewEventRules.resolve(a, calendar: cal)
        XCTAssertEqual(back?.start, timed.start)
        XCTAssertEqual(back?.end, timed.end)

        // 單日全天：結束給當天 23:59:59，或給隔天午夜，都是同一天
        let lastSecond = date(2026, 11, 18).addingTimeInterval(-1)
        let oneDay = CalEvent(id: "A", title: "生日", start: date(2026, 11, 17), end: lastSecond, isAllDay: true)
        XCTAssertEqual(NewEventRules.draft(editing: oneDay, calendar: cal).kind, .allDay)
        let oneDayMidnight = CalEvent(id: "A2", title: "生日", start: date(2026, 11, 17), end: date(2026, 11, 18), isAllDay: true)
        XCTAssertEqual(NewEventRules.draft(editing: oneDayMidnight, calendar: cal).kind, .allDay)
        let sameMoment = CalEvent(id: "A3", title: "生日", start: date(2026, 11, 17), end: date(2026, 11, 17), isAllDay: true)
        XCTAssertEqual(NewEventRules.draft(editing: sameMoment, calendar: cal).kind, .allDay)

        // 五天的旅遊
        let trip = CalEvent(id: "M", title: "東京", start: date(2026, 12, 5), end: date(2026, 12, 10).addingTimeInterval(-1), isAllDay: true)
        let m = NewEventRules.draft(editing: trip, calendar: cal)
        XCTAssertEqual(m.kind, .multiDay)
        XCTAssertEqual(m.rangeStart, date(2026, 12, 5))
        XCTAssertEqual(m.rangeEnd, date(2026, 12, 9))
        XCTAssertEqual(NewEventRules.rangeDayCount(m, calendar: cal), 5)
    }

    func testWhichEventsOurScreenCanEdit() {
        let short = CalEvent(id: "1", title: "a", start: date(2026, 11, 17, 6), end: date(2026, 11, 17, 7))
        let overnight = CalEvent(id: "2", title: "a", start: date(2026, 11, 17, 23), end: date(2026, 11, 18, 23))
        let long = CalEvent(id: "3", title: "a", start: date(2026, 11, 17, 6), end: date(2026, 11, 19, 7))
        let allDay = CalEvent(id: "4", title: "a", start: date(2026, 11, 17), end: date(2026, 11, 30), isAllDay: true)
        XCTAssertTrue(NewEventRules.canEditHere(short))
        XCTAssertTrue(NewEventRules.canEditHere(overnight))
        // 有時間又跨好幾天的：表單的開始、結束各有日期，改得了
        XCTAssertTrue(NewEventRules.canEditHere(long))
        XCTAssertTrue(NewEventRules.canEditHere(allDay))
        // 結束比開始早的怪資料交給系統的畫面
        let backwards = CalEvent(id: "5", title: "a", start: date(2026, 11, 17, 6), end: date(2026, 11, 17, 5))
        XCTAssertFalse(NewEventRules.canEditHere(backwards))
    }

    // MARK: 開始、結束各有日期與時間

    func testClock24HasNoMorningOrAfternoon() {
        XCTAssertEqual(EventText.clock24(0), "0:00")
        XCTAssertEqual(EventText.clock24(9 * 60 + 5), "9:05")
        XCTAssertEqual(EventText.clock24(17 * 60), "17:00")
        XCTAssertEqual(EventText.clock24(23 * 60 + 55), "23:55")
    }

    func testLongTimedEventRoundTrips() {
        // 12/1 晚上 8:00 到 12/8 晚上 10:30
        let trip = CalEvent(id: "K", title: "去韓國", start: date(2026, 12, 1, 20), end: date(2026, 12, 8, 22, 30))
        let d = NewEventRules.draft(editing: trip, calendar: cal)
        XCTAssertEqual(d.kind, .timed)
        XCTAssertEqual(NewEventRules.startDay(d), date(2026, 12, 1))
        XCTAssertEqual(d.startMinutes, 20 * 60)
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 12, 8))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 22 * 60 + 30)
        let back = NewEventRules.resolve(d, calendar: cal)
        XCTAssertEqual(back?.start, trip.start)
        XCTAssertEqual(back?.end, trip.end)
        XCTAssertEqual(EventText.when(d, calendar: cal), "12月1日 週二 下午 8:00 到 12月8日 週二 下午 10:30")
    }

    func testSettingStartAndEndOfTimedEvent() {
        // 11/17 下午 5:00 到 6:00
        var d = NewEventDraft(day: date(2026, 11, 17), startMinutes: 17 * 60)
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 17))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 18 * 60)

        // 改開始的日期：長度不變，結束跟著移
        d = NewEventRules.settingStartDay(date(2026, 11, 20), in: d, calendar: cal)
        XCTAssertEqual(d.day, date(2026, 11, 20))
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 20))
        XCTAssertEqual(d.durationMinutes, 60)

        // 改結束的日期：開始不動，鐘點不動
        d = NewEventRules.settingEndDay(date(2026, 11, 22), in: d, calendar: cal)
        XCTAssertEqual(d.day, date(2026, 11, 20))
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 22))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 18 * 60)
        XCTAssertEqual(d.durationMinutes, 2 * 1440 + 60)
        XCTAssertEqual(NewEventRules.resolve(d, calendar: cal)?.end, date(2026, 11, 22, 18))

        // 結束的日期不能比開始那天早
        XCTAssertEqual(NewEventRules.settingEndDay(date(2026, 11, 19), in: d, calendar: cal), d)

        // 改結束的鐘點：日期不動
        d = NewEventRules.settingEndClock(9 * 60 + 30, in: d, calendar: cal)
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 22))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 9 * 60 + 30)
        XCTAssertTrue(NewEventRules.hasValidTime(d))

        // 改開始的鐘點：結束跟著移
        let before = d.durationMinutes
        d = NewEventRules.settingStart(8 * 60, in: d)
        XCTAssertEqual(d.durationMinutes, before)

        // 直接點一種長度
        d = NewEventRules.settingDuration(120, in: d)
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 20))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 10 * 60)

        // 同一天裡把結束調到開始之前：顛倒，不能存
        d = NewEventRules.settingEndClock(7 * 60, in: d, calendar: cal)
        XCTAssertFalse(NewEventRules.hasValidTime(d))
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 20))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 7 * 60)
    }

    func testAllDaySwitchAndDays() {
        // 11/17 下午 5:00 到 6:00，設了「30 分鐘前」
        var d = NewEventDraft(day: date(2026, 11, 17), startMinutes: 17 * 60, reminder: .minutes30)
        d = NewEventRules.settingAllDay(true, in: d, calendar: cal)
        XCTAssertEqual(d.kind, .allDay)
        XCTAssertTrue(NewEventRules.isAllDay(d))
        // 有時間的提醒在整日用不了
        XCTAssertNil(d.reminder)
        XCTAssertEqual(NewEventRules.resolve(d, calendar: cal),
                       ResolvedEventTime(start: date(2026, 11, 17), end: date(2026, 11, 17), isAllDay: true))

        // 結束改到 11/19：變成三天
        d = NewEventRules.settingEndDay(date(2026, 11, 19), in: d, calendar: cal)
        XCTAssertEqual(d.kind, .multiDay)
        XCTAssertEqual(NewEventRules.rangeDayCount(d, calendar: cal), 3)
        XCTAssertEqual(NewEventRules.resolve(d, calendar: cal),
                       ResolvedEventTime(start: date(2026, 11, 17), end: date(2026, 11, 19), isAllDay: true))

        // 開始改到 11/24：天數不變，結束跟著移到 11/26
        d = NewEventRules.settingStartDay(date(2026, 11, 24), in: d, calendar: cal)
        XCTAssertEqual(NewEventRules.startDay(d), date(2026, 11, 24))
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 26))

        // 結束改回開始那天：變回單日
        d = NewEventRules.settingEndDay(date(2026, 11, 24), in: d, calendar: cal)
        XCTAssertEqual(d.kind, .allDay)
        XCTAssertNil(d.rangeStart)

        // 關掉整日：鐘點用回原本的下午 5:00 到 6:00
        d = NewEventRules.settingAllDay(false, in: d, calendar: cal)
        XCTAssertEqual(d.kind, .timed)
        XCTAssertEqual(d.day, date(2026, 11, 24))
        XCTAssertEqual(d.startMinutes, 17 * 60)
        XCTAssertEqual(NewEventRules.endDay(d, calendar: cal), date(2026, 11, 24))
        XCTAssertEqual(NewEventRules.endClock(d, calendar: cal), 18 * 60)

        // 跨日的有時間行程開整日：起訖兩天都留著
        let long = NewEventRules.settingEndDay(date(2026, 11, 26), in: d, calendar: cal)
        let whole = NewEventRules.settingAllDay(true, in: long, calendar: cal)
        XCTAssertEqual(whole.kind, .multiDay)
        XCTAssertEqual(whole.rangeStart, date(2026, 11, 24))
        XCTAssertEqual(whole.rangeEnd, date(2026, 11, 26))
    }

    func testSameTimeAndReminderMatching() {
        let a = NewEventDraft(title: "a", day: date(2026, 11, 17), startMinutes: 540)
        var b = a
        b.title = "b"
        b.notes = "x"
        XCTAssertTrue(NewEventRules.hasSameTime(a, b))
        b.durationMinutes = 30
        XCTAssertFalse(NewEventRules.hasSameTime(a, b))

        XCTAssertEqual(EventReminder.matching(offsetSeconds: -1800, isAllDay: false), .minutes30)
        XCTAssertEqual(EventReminder.matching(offsetSeconds: 9 * 3600, isAllDay: true), .sameDayMorning)
        // 15 分鐘前不在表單的選項裡
        XCTAssertNil(EventReminder.matching(offsetSeconds: -900, isAllDay: false))
        // 全天行程不會對到「準時」
        XCTAssertNil(EventReminder.matching(offsetSeconds: 0, isAllDay: true))
    }

    func testSideMenuOrder() {
        XCTAssertEqual(ViewKind.allCases, [.agenda, .day, .threeDay, .week, .month])
    }

    // MARK: 天氣

    private func sampleCache(city: String = "taipei", at fetched: Date) -> WeatherCache {
        let credit = WeatherCredit(
            markLight: URL(string: "https://example.com/light.png")!,
            markDark: URL(string: "https://example.com/dark.png")!,
            legalPage: URL(string: "https://example.com/legal")!
        )
        let days = [
            DayForecast(dayKey: "2026-11-16", symbolName: "cloud", condition: "多雲", high: 28, low: 22, rainPercent: 40),
            DayForecast(dayKey: "2026-11-17", symbolName: "sun.max", condition: "晴", high: 30, low: 21, rainPercent: 0)
        ]
        return WeatherCache(cityID: city, fetchedAt: fetched, days: days, credit: credit)
    }

    func testEveryCityHasCoordinatesInsideTaiwanArea() {
        for city in WeatherCity.all {
            XCTAssertTrue((21.5...26.5).contains(city.latitude), city.name)
            XCTAssertTrue((118.0...122.5).contains(city.longitude), city.name)
        }
        XCTAssertNotNil(TimeZone(identifier: WeatherCity.timeZoneID))
    }

    func testWeatherDayKeyAndLookup() {
        XCTAssertEqual(WeatherRules.dayKey(date(2026, 1, 5, 23, 59), calendar: cal), "2026-01-05")
        let cache = sampleCache(at: date(2026, 11, 16, 8, 12))
        let today = date(2026, 11, 16)
        let hit = WeatherRules.forecast(in: cache, cityID: "taipei", day: date(2026, 11, 17, 15), today: today, calendar: cal)
        XCTAssertEqual(hit?.high, 30)
        // 沒有那一天的資料（超過十天）
        XCTAssertNil(WeatherRules.forecast(in: cache, cityID: "taipei", day: date(2026, 12, 1), today: today, calendar: cal))
        // 已經過去的日子，就算手機裡還留著也不顯示
        XCTAssertNil(WeatherRules.forecast(in: cache, cityID: "taipei", day: date(2026, 11, 16), today: date(2026, 11, 17), calendar: cal))
        // 換了縣市、還沒選縣市、手機裡沒有資料
        XCTAssertNil(WeatherRules.forecast(in: cache, cityID: "tainan", day: today, today: today, calendar: cal))
        XCTAssertNil(WeatherRules.forecast(in: cache, cityID: nil, day: today, today: today, calendar: cal))
        XCTAssertNil(WeatherRules.forecast(in: nil, cityID: "taipei", day: today, today: today, calendar: cal))
    }

    func testWeatherNeedsRefresh() {
        let fetched = date(2026, 11, 16, 8, 0)
        let cache = sampleCache(at: fetched)
        XCTAssertTrue(WeatherRules.needsRefresh(nil, cityID: "taipei", now: fetched))
        XCTAssertFalse(WeatherRules.needsRefresh(cache, cityID: "taipei", now: date(2026, 11, 16, 10, 59)))
        XCTAssertTrue(WeatherRules.needsRefresh(cache, cityID: "taipei", now: date(2026, 11, 16, 11, 0)))
        XCTAssertTrue(WeatherRules.needsRefresh(cache, cityID: "tainan", now: date(2026, 11, 16, 8, 1)))
        // 時鐘被往回調
        XCTAssertTrue(WeatherRules.needsRefresh(cache, cityID: "taipei", now: date(2026, 11, 16, 7, 0)))
    }

    func testWeatherRejectsBrokenData() {
        let good = DayForecast(dayKey: "2026-11-16", symbolName: "cloud", condition: "多雲", high: 28, low: 22, rainPercent: 40)
        XCTAssertTrue(WeatherRules.isValid(good))
        var bad = good
        bad.symbolName = ""
        XCTAssertFalse(WeatherRules.isValid(bad))
        bad = good
        bad.low = 35
        XCTAssertFalse(WeatherRules.isValid(bad))
        bad = good
        bad.high = 999
        XCTAssertFalse(WeatherRules.isValid(bad))
        bad = good
        bad.rainPercent = 140
        XCTAssertFalse(WeatherRules.isValid(bad))
    }

    func testWeatherTexts() {
        let f = DayForecast(dayKey: "2026-11-16", symbolName: "cloud", condition: "多雲", high: 28, low: 22, rainPercent: 40)
        XCTAssertEqual(WeatherRules.temperatures(f), "22–28°")
        XCTAssertEqual(WeatherRules.line(f), "多雲 · 22–28° · 降雨 40%")
        var blank = f
        blank.condition = " "
        XCTAssertEqual(WeatherRules.line(blank), "22–28° · 降雨 40%")
        let now = date(2026, 11, 16, 20, 0)
        XCTAssertEqual(WeatherRules.updatedText(date(2026, 11, 16, 8, 12), now: now, calendar: cal), "今天 08:12")
        XCTAssertEqual(WeatherRules.updatedText(date(2026, 11, 15, 23, 5), now: now, calendar: cal), "11月15日 23:05")
    }

    func testWeatherCacheRoundTrips() throws {
        let cache = sampleCache(at: date(2026, 11, 16, 8, 12))
        let round = try JSONDecoder().decode(WeatherCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(round, cache)
    }

    // MARK: 小工具

    func testWidgetTodayDropsEndedHiddenHolidayAndRoutine() {
        settings.hiddenCalendarIDs = ["X"]
        let now = date(2026, 11, 17, 14, 0)
        let events = [
            ev("done", "晨會", date(2026, 11, 17, 9, 0)),
            // 13:00 到 14:00，現在剛好 14:00，算結束了
            ev("justDone", "午餐", date(2026, 11, 17, 13, 0)),
            ev("going", "看牙", date(2026, 11, 17, 13, 30), cal: "M"),
            ev("later", "接小孩", date(2026, 11, 17, 16, 0), cal: "E"),
            allDay("full", "繳房租", date(2026, 11, 17), days: 1),
            ev("hidden", "不看的", date(2026, 11, 17, 15, 0), cal: "X"),
            allDay("holiday", "某節", date(2026, 11, 17), days: 1, cal: "H"),
            ev("routine", "吃藥", date(2026, 11, 17, 18, 0), daily: true),
            ev("tomorrow", "開會", date(2026, 11, 18, 10, 0))
        ]
        let w = WidgetRules.today(events: events, now: now, calendar: cal, settings: settings)
        XCTAssertEqual(w.rows.map(\.id), ["full", "going", "later"])
        XCTAssertEqual(w.rows.map(\.timeText), ["全天", "13:30", "16:00"])
        XCTAssertEqual(w.rows.map(\.categoryID), ["life", "life", "rest"])
        XCTAssertEqual(w.moreCount, 0)
    }

    func testWidgetTodayBandFirstAndLimit() {
        let now = date(2026, 11, 17, 8, 0)
        let events = [
            ev("c", "C", date(2026, 11, 17, 15, 0)),
            ev("a", "A", date(2026, 11, 17, 9, 0)),
            allDay("full", "繳房租", date(2026, 11, 17), days: 1),
            ev("b", "B", date(2026, 11, 17, 11, 0)),
            allDay("trip", "東京", date(2026, 11, 16), days: 3)
        ]
        let w = WidgetRules.today(events: events, now: now, calendar: cal, settings: settings)
        XCTAssertEqual(w.rows.map(\.id), ["trip", "full", "a"])
        XCTAssertEqual(w.rows[0].timeText, "全天")
        XCTAssertEqual(w.moreCount, 2)

        let roomy = WidgetRules.today(events: events, now: now, calendar: cal, settings: settings, limit: 10)
        XCTAssertEqual(roomy.rows.map(\.id), ["trip", "full", "a", "b", "c"])
        XCTAssertEqual(roomy.moreCount, 0)

        let none = WidgetRules.today(events: events, now: now, calendar: cal, settings: settings, limit: 0)
        XCTAssertTrue(none.rows.isEmpty)
        XCTAssertEqual(none.moreCount, 5)
    }

    func testWidgetTodayChangesDayAtMidnightAndUsesShortName() {
        settings.shortNames = ["long": "回診"]
        let events = [
            // 22:00 到隔天 01:00，跟蒜日子一樣只算在開始那天
            ev("late", "看電影", date(2026, 11, 17, 22, 0), hours: 3),
            ev("long", "台大醫院心臟內科回診拿藥", date(2026, 11, 18, 10, 0), cal: "M")
        ]
        let before = WidgetRules.today(events: events, now: date(2026, 11, 17, 23, 59), calendar: cal, settings: settings)
        XCTAssertEqual(before.rows.map(\.id), ["late"])

        let after = WidgetRules.today(events: events, now: date(2026, 11, 18, 0, 0), calendar: cal, settings: settings)
        XCTAssertEqual(after.rows.map(\.id), ["long"])
        XCTAssertEqual(after.rows[0].label, "回診")

        let empty = WidgetRules.today(events: [], now: date(2026, 11, 18, 0, 0), calendar: cal, settings: settings)
        XCTAssertEqual(empty, WidgetToday(rows: [], moreCount: 0))
    }

    func testWidgetTodayHolidayAndLimited() {
        let now = date(2026, 11, 17, 8, 0)
        let events = [
            allDay("holiday", "某節", date(2026, 11, 17), days: 1, cal: "H"),
            ev("a", "A", date(2026, 11, 17, 9, 0)),
            ev("b", "B", date(2026, 11, 17, 11, 0)),
            ev("c", "C", date(2026, 11, 17, 15, 0)),
            ev("d", "D", date(2026, 11, 17, 17, 0))
        ]
        let w = WidgetRules.today(events: events, now: now, calendar: cal, settings: settings)
        XCTAssertEqual(w.holiday, "某節")
        XCTAssertEqual(w.moreCount, 1)
        let two = w.limited(to: 2)
        XCTAssertEqual(two.rows.map(\.id), ["a", "b"])
        XCTAssertEqual(two.moreCount, 2)
        XCTAssertEqual(two.holiday, "某節")
        // 比現有的多：照原樣
        XCTAssertEqual(w.limited(to: 9), w)
        XCTAssertNil(WidgetRules.today(events: events, now: date(2026, 11, 18), calendar: cal, settings: settings).holiday)
    }

    func testWidgetMomentsAreEventEndsAndMidnight() {
        settings.hiddenCalendarIDs = ["X"]
        let now = date(2026, 11, 17, 10, 0)
        let events = [
            ev("done", "晨會", date(2026, 11, 17, 8, 0)),
            ev("a", "A", date(2026, 11, 17, 11, 0)),
            // 跟 A 同時結束，只排一次
            ev("b", "B", date(2026, 11, 17, 10, 30), hours: 1.5),
            ev("hidden", "不看的", date(2026, 11, 17, 15, 0), cal: "X"),
            allDay("full", "繳房租", date(2026, 11, 17), days: 1),
            ev("routine", "吃藥", date(2026, 11, 17, 18, 0), daily: true),
            ev("tomorrow", "開會", date(2026, 11, 18, 9, 0)),
            ev("later", "後天的", date(2026, 11, 19, 9, 0))
        ]
        let moments = WidgetRules.moments(events: events, now: now, calendar: cal, settings: settings)
        XCTAssertEqual(moments, [
            now, date(2026, 11, 17, 12, 0), date(2026, 11, 18), date(2026, 11, 18, 10, 0)
        ])
        // 沒有行程也要過午夜
        XCTAssertEqual(
            WidgetRules.moments(events: [], now: now, calendar: cal, settings: settings),
            [now, date(2026, 11, 18)]
        )
        // 週六到週日跨過一週的邊界，明天的也要排到
        let saturday = date(2026, 11, 21, 20, 0)
        let sunday = [ev("sun", "爬山", date(2026, 11, 22, 7, 0))]
        XCTAssertEqual(
            WidgetRules.moments(events: sunday, now: saturday, calendar: cal, settings: settings),
            [saturday, date(2026, 11, 22), date(2026, 11, 22, 8, 0)]
        )
    }

    func testWidgetLinkOnlyAcceptsToday() throws {
        let today = try XCTUnwrap(WidgetLink.today)
        XCTAssertTrue(WidgetLink.opensToday(today))
        for text in ["suanrizi://today/", "suanrizi://today?date=2026-11-17", "suanrizi://today#x",
                     "suanrizi://event", "suanrizi://", "https://today", "other://today"] {
            XCTAssertFalse(WidgetLink.opensToday(try XCTUnwrap(URL(string: text))), text)
        }
    }

    func testWidgetSettingsMissingIsDefaultButBrokenThrows() throws {
        XCTAssertEqual(try WidgetShared.settings(from: nil), AppSettings())
        let saved = AppSettings(hiddenCalendarIDs: ["X"])
        XCTAssertEqual(try WidgetShared.settings(from: JSONEncoder().encode(saved)), saved)
        XCTAssertThrowsError(try WidgetShared.settings(from: Data("壞掉".utf8)))
    }

    func testDisplayCalendarFollowsSettings() throws {
        let taipei = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
        let device = AppSettings().displayCalendar(device: taipei)
        XCTAssertEqual(device.timeZone, taipei)
        XCTAssertEqual(device.firstWeekday, 1)
        let tokyo = AppSettings(weekStartsOnMonday: true, usesDeviceTimeZone: false, timeZoneID: "Asia/Tokyo")
            .displayCalendar(device: taipei)
        XCTAssertEqual(tokyo.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(tokyo.firstWeekday, 2)
    }

    func testLoopWheelWrapsAroundBothEnds() {
        // 小時：23 的下一列是 0，0 的上一列是 23
        let at23 = LoopWheelRules.middleRow(index: 23, count: 24)
        XCTAssertEqual(LoopWheelRules.index(ofRow: at23, count: 24), 23)
        XCTAssertEqual(LoopWheelRules.index(ofRow: at23 + 1, count: 24), 0)
        let at0 = LoopWheelRules.middleRow(index: 0, count: 24)
        XCTAssertEqual(LoopWheelRules.index(ofRow: at0 - 1, count: 24), 23)
        // 分鐘：59 的下一列是 0
        let at59 = LoopWheelRules.middleRow(index: 59, count: 60)
        XCTAssertEqual(LoopWheelRules.index(ofRow: at59 + 1, count: 60), 0)
        // 打開時上下都還有很多列
        XCTAssertGreaterThan(at0, 24 * 5)
        XCTAssertLessThan(at23, LoopWheelRules.rowCount(24) - 24 * 5)
    }

    func testLoopWheelTurnsTheShortWayWhenValueChangesOutside() {
        let at23 = LoopWheelRules.middleRow(index: 23, count: 24)
        // 23 點變 0 點：往下一格，不是往回轉 23 格
        XCTAssertEqual(LoopWheelRules.nearestRow(toIndex: 0, from: at23, count: 24), at23 + 1)
        // 0 點變 22 點：往上兩格
        let at0 = LoopWheelRules.middleRow(index: 0, count: 24)
        XCTAssertEqual(LoopWheelRules.nearestRow(toIndex: 22, from: at0, count: 24), at0 - 2)
        // 沒變就不動
        XCTAssertEqual(LoopWheelRules.nearestRow(toIndex: 23, from: at23, count: 24), at23)
        // 已經在長條最尾巴還要往下：回中間那一輪
        let last = LoopWheelRules.rowCount(24) - 1
        XCTAssertEqual(LoopWheelRules.nearestRow(toIndex: 0, from: last, count: 24), LoopWheelRules.middleRow(index: 0, count: 24))
        // 最頭還要往上也一樣
        XCTAssertEqual(LoopWheelRules.nearestRow(toIndex: 23, from: 0, count: 24), LoopWheelRules.middleRow(index: 23, count: 24))
    }

    func testReviewTimingNeedsThreeDaysFiveSavesAndNewVersion() {
        let first = date(2026, 12, 1, 9)
        var s = AppSettings(firstOpenedAt: first, savedEventCount: 5)
        // 剛好滿 3 天、存了 5 次：可以請
        XCTAssertTrue(ReviewTiming.shouldAsk(s, version: "1.0.1", now: date(2026, 12, 4, 9)))
        // 差一分鐘才滿 3 天：不請
        XCTAssertFalse(ReviewTiming.shouldAsk(s, version: "1.0.1", now: date(2026, 12, 4, 8, 59)))
        // 只存了 4 次：不請
        s.savedEventCount = 4
        XCTAssertFalse(ReviewTiming.shouldAsk(s, version: "1.0.1", now: date(2026, 12, 10)))
        s.savedEventCount = 9
        // 這個版本請過了：不請；換新版本：可以再請
        s.reviewAskedVersion = "1.0.1"
        XCTAssertFalse(ReviewTiming.shouldAsk(s, version: "1.0.1", now: date(2026, 12, 10)))
        XCTAssertTrue(ReviewTiming.shouldAsk(s, version: "1.1.0", now: date(2026, 12, 10)))
        // 讀不到版本號、沒記到第一次打開的時間：一律不請
        XCTAssertFalse(ReviewTiming.shouldAsk(s, version: "", now: date(2026, 12, 10)))
        s.firstOpenedAt = nil
        XCTAssertFalse(ReviewTiming.shouldAsk(s, version: "1.1.0", now: date(2026, 12, 10)))
    }

    func testOldSettingsWithoutReviewFieldsStillDecode() throws {
        let old = try JSONEncoder().encode(AppSettings(showLunar: false))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        dict.removeValue(forKey: "savedEventCount")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.savedEventCount, 0)
        XCTAssertNil(decoded.firstOpenedAt)
        XCTAssertNil(decoded.reviewAskedVersion)
        XCTAssertFalse(decoded.showLunar)
    }

    // MARK: 左右滑放手

    func testSwipeWithoutFlickNeedsDistance() {
        XCTAssertTrue(SwipeRules.commits(distance: 40, velocity: 0))
        XCTAssertFalse(SwipeRules.commits(distance: 39, velocity: 0))
        // 放手時還有一點速度，但不到甩的程度：一樣看距離
        XCTAssertFalse(SwipeRules.commits(distance: 20, velocity: 299))
        XCTAssertTrue(SwipeRules.commits(distance: 60, velocity: -299))
    }

    func testSwipeFlickDecidesByDirection() {
        // 甩得快，距離不到也算
        XCTAssertTrue(SwipeRules.commits(distance: 12, velocity: 300))
        // 拉得很遠才往回甩：反悔，不算
        XCTAssertFalse(SwipeRules.commits(distance: 200, velocity: -300))
        // 手指停在反方向：再快也不算
        XCTAssertFalse(SwipeRules.commits(distance: -10, velocity: 900))
        XCTAssertFalse(SwipeRules.commits(distance: 0, velocity: 900))
    }

    func testSwipeResistanceNeverPassesLimit() {
        XCTAssertEqual(SwipeRules.resisted(-50), 0)
        XCTAssertEqual(SwipeRules.resisted(0), 0)
        // 越拉越遠，但每一次都比手指動得少、也不會超過上限
        var last = 0.0
        for distance in [10.0, 50, 200, 2000] {
            let moved = SwipeRules.resisted(distance)
            XCTAssertGreaterThan(moved, last)
            XCTAssertLessThan(moved, distance)
            XCTAssertLessThan(moved, SwipeRules.resistLimit)
            last = moved
        }
    }
}
