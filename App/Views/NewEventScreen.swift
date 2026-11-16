import SwiftUI
import UIKit
import EventKit
import CalendarCore

/// 蒜日子自己的新增行程畫面（規格第 20 節）。
/// 帶入什麼、起訖怎麼推、月曆點兩下、畫面上的日期文字都問 Core 的 `NewEventRules`、`EventText`；
/// 寫進系統行事曆交給 `EventStore.addEvent`。修改既有的行程照舊開系統的編輯畫面（`EventEditor`）。
struct NewEventScreen: View {
    @Environment(AppModel.self) private var app

    /// 月曆照哪個時區、一週從哪天開始，這裡就照一樣的
    let calendar: Calendar
    let close: () -> Void

    @State private var draft: NewEventDraft
    /// 打開時的樣子。跟它不一樣就是使用者動過了，取消前要先問。
    @State private var pristine: NewEventDraft
    /// 月曆現在翻到哪個月
    @State private var shownMonth: Date
    @State private var pickingOtherDay = false
    /// 時間卡展開時正在調開始還是結束；nil 是收著
    @State private var timeField: TimeField?
    @State private var pickingCalendar = false
    @State private var showLocation = false
    @State private var showNotes = false
    @State private var problem: String?
    @State private var confirmDiscard = false
    /// 存好、而且要分享時，換成「已加進行事曆」那一頁
    @State private var saved: SavedEvent?
    @FocusState private var focus: Field?

    enum TimeField { case start, end }
    enum Field { case title, location, notes }

    /// 標題那一格的高度、滾輪的高度
    private let titleHeight: CGFloat = 64
    private let wheelHeight: CGFloat = 150

    init(day: Date, calendar: Calendar, close: @escaping () -> Void) {
        let first = NewEventRules.initialDraft(day: day, now: Date(), calendar: calendar)
        _draft = State(initialValue: first)
        _pristine = State(initialValue: first)
        _shownMonth = State(initialValue: first.day)
        self.calendar = calendar
        self.close = close
    }

    var body: some View {
        Group {
            if let saved {
                NewEventSavedView(saved: saved, calendar: calendar, close: close)
            } else {
                form
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // 動過之後不能直接往下滑掉，要按「取消」確認，免得打到一半不見
        .interactiveDismissDisabled(isDirty && saved == nil)
    }

    // MARK: 狀態

    private var isDirty: Bool { draft != pristine }

    private var canSave: Bool {
        !draft.cleanTitle.isEmpty
            && draft.calendarID != nil
            && NewEventRules.resolve(draft, calendar: calendar) != nil
    }

    /// 有加入蒜日子、寫得進去、不是節日的行事曆，照顯示順序
    private var writableCalendars: [EKCalendar] {
        let holidays = app.settings.value.holidayCalendarIDs
        return app.vm.shownCalendars.filter {
            $0.allowsContentModifications && !holidays.contains($0.calendarIdentifier)
        }
    }

    private var selectedCalendar: EKCalendar? {
        writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
    }

    private func setUp() {
        guard draft.calendarID == nil else { return }
        let picked = NewEventRules.pickCalendar(
            lastUsed: app.settings.value.lastEventCalendarID,
            systemDefault: app.store.defaultCalendarID,
            available: writableCalendars.map(\.calendarIdentifier)
        )
        draft.calendarID = picked
        pristine.calendarID = picked
        focus = .title
    }

    private func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            close()
        }
    }

    private func save() {
        guard let time = NewEventRules.resolve(draft, calendar: calendar) else {
            problem = "先在月曆上點開始的那一天。"
            return
        }
        let result = app.store.addEvent(draft, time: time)
        guard let event = result.event else {
            problem = result.problem ?? "沒有存成功，請再試一次。"
            return
        }
        problem = nil
        app.settings.update { $0.lastEventCalendarID = draft.calendarID }
        guard draft.wantsShare else {
            close()
            return
        }
        focus = nil
        saved = SavedEvent(
            draft: draft,
            time: time,
            event: event,
            calendarLine: selectedCalendar.map(calendarLine) ?? "",
            dotColor: selectedCalendar.map { app.vm.color(categoryID(of: $0)) } ?? Theme.accent
        )
    }

    // MARK: 表單

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                titleField
                if draft.kind != .multiDay { daySection }
                durationSection
                if draft.kind == .multiDay {
                    monthCard(isRange: true)
                } else {
                    timeCard
                }
                calendarSection
                optionsSection
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s2)
            .padding(.bottom, DT.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .onAppear { setUp() }
        .confirmationDialog("放棄這筆行程？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放棄", role: .destructive) { close() }
            Button("繼續編輯", role: .cancel) {}
        }
    }

    private var topBar: some View {
        ZStack {
            Text("新增行程")
                .dFont(DT.TypeScale.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: cancel) {
                    Text("取消")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.sub)
                        .frame(minWidth: DT.Size.touch, minHeight: DT.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                Spacer()
            }
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.top, DT.Space.s3)
        .padding(.bottom, DT.Space.s1)
        .background(Theme.bg)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            if let problem {
                Text(problem)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.destructive)
            }
            WideButton(title: draft.wantsShare ? "儲存並分享" : "儲存", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.vertical, DT.Space.s3)
        .background(Theme.bg)
    }

    private var titleField: some View {
        TextField("要做什麼？", text: $draft.title)
            .dFont(DT.TypeScale.title2)
            .foregroundStyle(Theme.ink)
            .focused($focus, equals: .title)
            .submitLabel(.done)
            .padding(.horizontal, DT.Space.s4)
            .frame(minHeight: titleHeight)
            .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
            .accessibilityLabel("標題")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .dFont(DT.TypeScale.footnote)
            .foregroundStyle(Theme.sub)
            .padding(.horizontal, DT.Space.s1)
    }

    /// 一顆可以選的膠囊：選到的是主色底
    private func chip(_ title: String, isOn: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s1) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .dFont(DT.TypeScale.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, DT.Space.s2)
            .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
            .background(Capsule().fill(isOn ? Theme.accent : Theme.card))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 哪一天

    private var daySection: some View {
        let quick = NewEventRules.quickDayIndex(of: draft.day, today: app.vm.today, calendar: calendar)
        let names = ["今天", "明天", "後天"]
        return VStack(alignment: .leading, spacing: DT.Space.s2) {
            sectionLabel("哪一天")
            HStack(spacing: DT.Space.s2) {
                ForEach(0..<NewEventRules.quickDayCount, id: \.self) { index in
                    chip(names[index], isOn: quick == index) {
                        if let day = calendar.date(byAdding: .day, value: index, to: app.vm.today) {
                            draft.day = calendar.startOfDay(for: day)
                        }
                        pickingOtherDay = false
                    }
                }
                chip(
                    quick == nil ? EventText.shortDay(draft.day, calendar: calendar) : "其他",
                    isOn: quick == nil,
                    systemImage: "calendar"
                ) {
                    shownMonth = draft.day
                    pickingOtherDay.toggle()
                }
                .accessibilityLabel(quick == nil
                    ? "其他日期，目前是\(EventText.day(draft.day, calendar: calendar))"
                    : "選其他日期")
            }
            if pickingOtherDay {
                monthCard(isRange: false)
            }
        }
    }

    // MARK: 多久

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            sectionLabel("多久")
            HStack(spacing: DT.Space.s2) {
                ForEach(NewEventRules.quickDurations, id: \.self) { minutes in
                    chip(EventText.duration(minutes), isOn: draft.kind == .timed && draft.durationMinutes == minutes) {
                        leaveMultiDay()
                        draft.kind = .timed
                        draft.durationMinutes = minutes
                        fitReminder()
                    }
                }
                chip("整日", isOn: draft.kind == .allDay) {
                    leaveMultiDay()
                    draft.kind = .allDay
                    timeField = nil
                    fitReminder()
                }
                chip("多天", isOn: draft.kind == .multiDay) {
                    draft.kind = .multiDay
                    timeField = nil
                    pickingOtherDay = false
                    shownMonth = draft.rangeStart ?? draft.day
                    fitReminder()
                }
            }
        }
    }

    /// 從「多天」換回單日：已經點過開始日就沿用那一天
    private func leaveMultiDay() {
        guard draft.kind == .multiDay, let start = draft.rangeStart else { return }
        draft.day = start
    }

    private func fitReminder() {
        draft.reminder = NewEventRules.reminder(draft.reminder, fitting: draft.kind)
    }

    // MARK: 時間卡

    private var timeCard: some View {
        VStack(spacing: DT.Space.s2) {
            if draft.kind == .timed, let field = timeField {
                timeEditor(field)
            } else {
                timeSummary
            }
        }
        .padding(DT.Space.s2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    private var dateLine: String {
        let day = EventText.day(draft.day, calendar: calendar)
        guard let repeats = draft.repeats else { return day }
        return day + "起，" + repeats.summary(from: draft.day, calendar: calendar)
    }

    private var timeSummary: some View {
        let isTimed = draft.kind == .timed
        return Button {
            if isTimed { timeField = .start }
        } label: {
            HStack(spacing: DT.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLine)
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                    Text(isTimed
                        ? EventText.timeRange(startMinutes: draft.startMinutes, durationMinutes: draft.durationMinutes)
                        : "整日")
                        .dFont(DT.TypeScale.title3)
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isTimed {
                    Text("改時間")
                        .dFont(DT.TypeScale.callout)
                        .foregroundStyle(Theme.strong)
                }
            }
            .padding(.horizontal, DT.Space.s2)
            .frame(minHeight: DT.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!isTimed)
    }

    private func timeEditor(_ field: TimeField) -> some View {
        VStack(spacing: DT.Space.s2) {
            HStack(spacing: DT.Space.s2) {
                timeTab("開始", EventText.time(draft.startMinutes), isOn: field == .start) { timeField = .start }
                timeTab(
                    draft.endsNextDay ? "結束（隔天）" : "結束",
                    EventText.time(draft.endMinutes),
                    isOn: field == .end
                ) { timeField = .end }
            }
            wheels(field)
            HStack {
                Text(field == .start
                    ? "結束時間會跟著往後移"
                    : "共 " + EventText.duration(draft.durationMinutes))
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                Spacer()
                Button {
                    timeField = nil
                } label: {
                    Text("完成")
                        .dFont(DT.TypeScale.callout)
                        .foregroundStyle(Theme.strong)
                        .frame(minWidth: DT.Size.touch, minHeight: DT.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, DT.Space.s2)
        }
    }

    private func timeTab(_ label: String, _ value: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(isOn ? Theme.strong : Theme.sub)
                Text(value)
                    .dFont(DT.TypeScale.title3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, DT.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(isOn ? Theme.soft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label) \(value)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 三個滾輪：上午下午、幾點、幾分。系統的時間滾輪不能設成 5 分鐘一格，所以自己排。
    private func wheels(_ field: TimeField) -> some View {
        let minutes = field == .start ? draft.startMinutes : draft.endMinutes
        let afternoon = Binding<Bool>(
            get: { EventText.isAfternoon(minutes) },
            set: { setClock(field, afternoon: $0, hour: EventText.hour12(minutes), minute: minutes % 60) }
        )
        let hour = Binding<Int>(
            get: { EventText.hour12(minutes) },
            set: { setClock(field, afternoon: EventText.isAfternoon(minutes), hour: $0, minute: minutes % 60) }
        )
        let minute = Binding<Int>(
            get: { minutes % 60 },
            set: { setClock(field, afternoon: EventText.isAfternoon(minutes), hour: EventText.hour12(minutes), minute: $0) }
        )
        return HStack(spacing: 0) {
            Picker("上午或下午", selection: afternoon) {
                Text("上午").tag(false)
                Text("下午").tag(true)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("幾點", selection: hour) {
                ForEach(1...12, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("幾分", selection: minute) {
                ForEach(minuteOptions(including: minutes % 60), id: \.self) { value in
                    Text(value < 10 ? "0\(value)" : "\(value)").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .pickerStyle(.wheel)
        .frame(height: wheelHeight)
    }

    /// 滾輪上的分鐘：每 5 分鐘一格。現在的分鐘數不在格子上（別處帶進來的）就補進去，不然滾輪會沒有選到的那一列。
    private func minuteOptions(including current: Int) -> [Int] {
        var options = Array(stride(from: 0, to: 60, by: NewEventRules.minuteStep))
        if !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    private func setClock(_ field: TimeField, afternoon: Bool, hour: Int, minute: Int) {
        let total = ((hour % 12) + (afternoon ? 12 : 0)) * 60 + minute
        switch field {
        case .start: draft = NewEventRules.settingStart(total, in: draft)
        case .end: draft = NewEventRules.settingEnd(total, in: draft)
        }
    }

    // MARK: 月曆（選其他日期、多天點兩下）

    private enum CellRole { case plain, edge, between }

    private func role(of day: Date, isRange: Bool) -> CellRole {
        guard isRange else { return day == draft.day ? .edge : .plain }
        guard let start = draft.rangeStart else { return .plain }
        if day == start || day == draft.rangeEnd { return .edge }
        if let end = draft.rangeEnd, day > start, day < end { return .between }
        return .plain
    }

    private func monthCard(isRange: Bool) -> some View {
        let cells = NewEventRules.monthCells(month: shownMonth, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(spacing: DT.Space.s2) {
            HStack {
                monthArrow("chevron.left", label: "上個月", months: -1)
                Spacer()
                Text(EventText.month(shownMonth, calendar: calendar))
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                monthArrow("chevron.right", label: "下個月", months: 1)
            }
            HStack(spacing: 0) {
                ForEach(app.vm.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .dFont(DT.TypeScale.caption)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: DT.Space.s1) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCell(cell, isRange: isRange)
                    } else {
                        Color.clear.frame(height: DT.Size.touch)
                    }
                }
            }
            if isRange {
                Hairline()
                rangeFooter
            }
        }
        .padding(DT.Space.s3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    private func monthArrow(_ systemName: String, label: String, months: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: months, to: shownMonth) {
                shownMonth = next
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: DT.Size.touch, height: DT.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Date, isRange: Bool) -> some View {
        let cellRole = role(of: day, isRange: isRange)
        let fill: Color
        switch cellRole {
        case .edge: fill = Theme.accent
        case .between: fill = Theme.soft
        case .plain: fill = Color.clear
        }
        return Button {
            if isRange {
                draft = NewEventRules.tappingRangeDay(day, in: draft, calendar: calendar)
            } else {
                draft.day = day
                pickingOtherDay = false
            }
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .dFont(DT.TypeScale.callout)
                .foregroundStyle(cellRole == .edge ? Theme.onAccent : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                .background(
                    RoundedRectangle(cornerRadius: cellRole == .edge ? DT.Radius.pill : 0).fill(fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(EventText.day(day, calendar: calendar))
        .accessibilityAddTraits(cellRole == .plain ? [] : .isSelected)
    }

    private var rangeFooter: some View {
        let count = NewEventRules.rangeDayCount(draft, calendar: calendar)
        return HStack(spacing: DT.Space.s2) {
            if let start = draft.rangeStart {
                if let end = draft.rangeEnd {
                    Text(EventText.day(start, calendar: calendar) + " → " + EventText.day(end, calendar: calendar))
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.ink)
                } else {
                    Text(EventText.day(start, calendar: calendar) + "開始，再點結束的那一天")
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.sub)
                }
            } else {
                Text("點開始的那一天")
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count) 天")
                    .dFont(DT.TypeScale.callout)
                    .foregroundStyle(Theme.strong)
            }
        }
        .padding(.horizontal, DT.Space.s1)
        .frame(minHeight: DT.Size.buttonCompact)
    }

    // MARK: 行事曆

    private struct CalendarGroup: Identifiable {
        let id: String
        let calendars: [EKCalendar]
    }

    /// 照帳號分組，帳號與組內的先後都照顯示順序
    private var calendarGroups: [CalendarGroup] {
        var accounts: [String] = []
        var byAccount: [String: [EKCalendar]] = [:]
        for cal in writableCalendars {
            let account = cal.source?.title ?? ""
            if byAccount[account] == nil { accounts.append(account) }
            byAccount[account, default: []].append(cal)
        }
        return accounts.map { CalendarGroup(id: $0, calendars: byAccount[$0] ?? []) }
    }

    private func categoryID(of cal: EKCalendar) -> String {
        app.settings.value.calendarCategory[cal.calendarIdentifier] ?? AppSettings.fallbackCategoryID
    }

    /// 「行事曆（iCloud）」
    private func calendarLine(_ cal: EKCalendar) -> String {
        guard let account = cal.source?.title, !account.isEmpty, account != cal.title else { return cal.title }
        return "\(cal.title)（\(account)）"
    }

    private func categoryDot(_ cal: EKCalendar) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(app.vm.color(categoryID(of: cal)))
            .frame(width: Theme.Grid.square, height: Theme.Grid.square)
            .accessibilityHidden(true)
    }

    private var calendarSection: some View {
        VStack(spacing: 0) {
            Button {
                pickingCalendar.toggle()
            } label: {
                HStack(spacing: DT.Space.s2) {
                    Text("行事曆")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.sub)
                    Spacer(minLength: DT.Space.s2)
                    if let cal = selectedCalendar {
                        categoryDot(cal)
                        Text(calendarLine(cal))
                            .dFont(DT.TypeScale.callout)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("沒有可以存的行事曆")
                            .dFont(DT.TypeScale.callout)
                            .foregroundStyle(Theme.destructive)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                }
                .frame(minHeight: DT.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("存到哪本行事曆")
            .accessibilityValue(selectedCalendar.map(calendarLine) ?? "沒有可以存的行事曆")
            if pickingCalendar {
                calendarList
            }
        }
        .padding(.horizontal, DT.Space.s4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    @ViewBuilder
    private var calendarList: some View {
        if writableCalendars.isEmpty {
            Hairline()
            Text("手機上沒有寫得進去、又有加入蒜日子的行事曆。到設定的「行事曆」加入一本，或建立新的。")
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DT.Space.s3)
        }
        ForEach(calendarGroups) { group in
            Hairline()
            if !group.id.isEmpty {
                Text(group.id)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DT.Space.s3)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                calendarRow(cal)
            }
        }
    }

    private func calendarRow(_ cal: EKCalendar) -> some View {
        let isSelected = cal.calendarIdentifier == draft.calendarID
        let category = app.settings.value.category(id: categoryID(of: cal))
        return Button {
            draft.calendarID = cal.calendarIdentifier
            pickingCalendar = false
        } label: {
            HStack(spacing: DT.Space.s3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                categoryDot(cal)
                Text(cal.title)
                    .dFont(isSelected ? DT.TypeScale.headline : DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(category.name)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
            }
            .frame(minHeight: DT.Size.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(cal.title)，類別是\(category.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: 五顆選項

    /// 選項的樣子：虛線框是還沒設，實心是設了
    private func optionLabel(_ title: String, systemImage: String, isSet: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(title)
                .dFont(DT.TypeScale.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isSet ? Theme.strong : Theme.sub)
        .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
        .background(Capsule().fill(isSet ? Theme.soft : Color.clear))
        .overlay(
            Capsule()
                .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .opacity(isSet ? 0 : 1)
        )
        .contentShape(Capsule())
    }

    private var optionsSection: some View {
        let hasLocation = showLocation || !draft.location.isEmpty
        let hasNotes = showNotes || !draft.notes.isEmpty
        let reminders = draft.kind == .timed ? EventReminder.timedCases : EventReminder.allDayCases
        return VStack(alignment: .leading, spacing: DT.Space.s3) {
            HStack(spacing: DT.Space.s2) {
                Menu {
                    Button("不提醒") { draft.reminder = nil }
                    ForEach(reminders, id: \.self) { option in
                        Button(option.label) { draft.reminder = option }
                    }
                } label: {
                    optionLabel("提醒", systemImage: "bell", isSet: draft.reminder != nil)
                }
                .accessibilityLabel("提醒")
                .accessibilityValue(draft.reminder?.label ?? "不提醒")
                Menu {
                    Button("不重複") { draft.repeats = nil }
                    ForEach(EventRepeat.allCases, id: \.self) { option in
                        Button(option.label) { draft.repeats = option }
                    }
                } label: {
                    optionLabel("重複", systemImage: "repeat", isSet: draft.repeats != nil)
                }
                .accessibilityLabel("重複")
                .accessibilityValue(draft.repeats?.label ?? "不重複")
                Button {
                    toggleField(.location)
                } label: {
                    optionLabel("地點", systemImage: "mappin.and.ellipse", isSet: hasLocation)
                }
                .buttonStyle(PressStyle())
                Button {
                    toggleField(.notes)
                } label: {
                    optionLabel("備註", systemImage: "text.alignleft", isSet: hasNotes)
                }
                .buttonStyle(PressStyle())
                Button {
                    draft.wantsShare.toggle()
                } label: {
                    optionLabel("分享", systemImage: "square.and.arrow.up", isSet: draft.wantsShare)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("存好之後分享給別人")
                .accessibilityAddTraits(draft.wantsShare ? .isSelected : [])
            }
            if draft.reminder != nil || draft.repeats != nil || hasLocation || hasNotes {
                optionDetails(hasLocation: hasLocation, hasNotes: hasNotes)
            }
        }
    }

    /// 點「地點」「備註」：還沒打開就打開並把游標放進去；開著而且是空的就收起來
    private func toggleField(_ field: Field) {
        switch field {
        case .location:
            if showLocation, draft.location.isEmpty {
                showLocation = false
                return
            }
            showLocation = true
        case .notes:
            if showNotes, draft.notes.isEmpty {
                showNotes = false
                return
            }
            showNotes = true
        case .title:
            break
        }
        focus = field
    }

    private func detailRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: DT.Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.strong)
                .frame(width: DT.Space.s6)
            Text(text)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: DT.Size.touch)
        .accessibilityElement(children: .combine)
    }

    private func optionDetails(hasLocation: Bool, hasNotes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reminder = draft.reminder {
                detailRow("bell", reminder.summary)
            }
            if let repeats = draft.repeats {
                detailRow("repeat", repeats.summary(from: draft.kind == .multiDay ? (draft.rangeStart ?? draft.day) : draft.day, calendar: calendar) + "重複")
            }
            if hasLocation {
                HStack(spacing: DT.Space.s3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.strong)
                        .frame(width: DT.Space.s6)
                    TextField("地點", text: $draft.location)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                        .focused($focus, equals: .location)
                        .submitLabel(.done)
                }
                .frame(minHeight: DT.Size.touch)
            }
            if hasNotes {
                HStack(alignment: .top, spacing: DT.Space.s3) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.strong)
                        .frame(width: DT.Space.s6)
                        .padding(.top, DT.Space.s3)
                    VStack(alignment: .leading, spacing: DT.Space.s1) {
                        TextField("備註", text: $draft.notes, axis: .vertical)
                            .dFont(DT.TypeScale.body)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3...8)
                            .focused($focus, equals: .notes)
                        Text("只能放文字。網址照貼就好。")
                            .dFont(DT.TypeScale.footnote)
                            .foregroundStyle(Theme.sub)
                    }
                    .padding(.vertical, DT.Space.s3)
                }
            }
        }
        .padding(.horizontal, DT.Space.s4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }
}

/// 剛存好的那一筆，給「已加進行事曆」那一頁用
struct SavedEvent {
    let draft: NewEventDraft
    let time: ResolvedEventTime
    let event: EKEvent
    /// 存進哪一本，例：「行事曆（iCloud）」
    let calendarLine: String
    let dotColor: Color
}

/// 存好之後的那一頁：只有表單上點亮「分享」才會出現（規格第 20.6 節）
struct NewEventSavedView: View {
    @Environment(AppModel.self) private var app

    let saved: SavedEvent
    let calendar: Calendar
    let close: () -> Void

    @State private var sharing: SharePayload?
    @State private var inviting = false
    @State private var message: String?
    @State private var messageIsProblem = false

    /// 打勾那個圓的直徑
    private let checkSize: CGFloat = 56

    struct SharePayload: Identifiable {
        let id = UUID()
        let text: String
        let file: URL
    }

    private var shareText: String { EventText.shareText(saved.draft, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                VStack(spacing: DT.Space.s3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: checkSize, height: checkSize)
                        .background(Circle().fill(Theme.soft))
                        .accessibilityHidden(true)
                    Text("已加進行事曆")
                        .dFont(DT.TypeScale.title2)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DT.Space.s8)
                summaryCard
                VStack(alignment: .leading, spacing: DT.Space.s3) {
                    Text("要找人一起嗎")
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                        .padding(.horizontal, DT.Space.s1)
                    WideButton(title: "分享給別人", systemImage: "square.and.arrow.up", action: share)
                    WideButton(title: "複製時間和標題", kind: .secondary, systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = shareText
                        message = "已複製"
                        messageIsProblem = false
                    }
                    if let message {
                        Text(message)
                            .dFont(DT.TypeScale.footnote)
                            .foregroundStyle(messageIsProblem ? Theme.destructive : Theme.strong)
                            .padding(.horizontal, DT.Space.s1)
                    }
                    inviteRow
                }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.bottom, DT.Space.s6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: close) {
                Text("完成")
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.button)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.bottom, DT.Space.s2)
            .background(Theme.bg)
        }
        .sheet(item: $sharing) { payload in
            ActivityView(items: [payload.text, payload.file])
        }
        .sheet(isPresented: $inviting) {
            EventEditor(store: app.store, event: saved.event, defaultDay: saved.time.start, calendar: calendar) {
                inviting = false
            }
            .ignoresSafeArea()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            Text(saved.draft.cleanTitle)
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(Theme.ink)
            Text(EventText.when(saved.draft, calendar: calendar))
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.sub)
            if !saved.calendarLine.isEmpty {
                HStack(spacing: DT.Space.s2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(saved.dotColor)
                        .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                        .accessibilityHidden(true)
                    Text(saved.calendarLine)
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(DT.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    private var inviteRow: some View {
        Button {
            inviting = true
        } label: {
            HStack(spacing: DT.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("用 Email 正式邀請")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                    Text("對方可以回覆要不要來。會開 iPhone 內建的畫面，在「邀請對象」填信箱。")
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.sub)
            }
            .padding(DT.Space.s4)
            .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    /// 把行事曆檔寫到暫存資料夾，連同那段文字交給 iPhone 的分享面板
    private func share() {
        let seed = saved.event.eventIdentifier ?? UUID().uuidString
        let ics = ICSFile.make(
            uid: seed + "@suanrizi",
            draft: saved.draft,
            time: saved.time,
            stamp: Date(),
            calendar: calendar
        )
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(ICSFile.fileName(title: saved.draft.cleanTitle))
        do {
            try Data(ics.utf8).write(to: file, options: .atomic)
        } catch {
            message = "沒辦法準備行事曆檔：\(error.localizedDescription)"
            messageIsProblem = true
            return
        }
        message = nil
        sharing = SharePayload(text: shareText, file: file)
    }
}

/// iPhone 的分享面板
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
