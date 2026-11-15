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
        settings = AppSettings(calendarCategory: ["W": "work", "M": "med", "E": "errand"], holidayCalendarIDs: ["H"])
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
        XCTAssertEqual(Classifier.categoryID(for: ev("2", "吃飯", date(2026, 11, 16, 10), cal: "?"), settings: settings), "trip")
    }

    func testKeywordRuleOverridesCalendar() {
        settings.keywordRules = [KeywordRule(keyword: "回診", categoryID: "med")]
        XCTAssertEqual(Classifier.categoryID(for: ev("1", "牙科回診", date(2026, 11, 16, 10)), settings: settings), "med")
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

    func testWeatherCityList() {
        XCTAssertEqual(WeatherCity.all.count, 22)
        XCTAssertEqual(Set(WeatherCity.all.map(\.id)).count, 22)
        XCTAssertNil(WeatherCity.find(nil))
        XCTAssertNil(WeatherCity.find("不存在"))
    }
}
