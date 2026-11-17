import SwiftUI
import UIKit
import EventKit
import CalendarCore

/// 蒜日子自己的新增與編輯行程畫面（規格第 20 節）。
/// 帶入什麼、起訖怎麼推、月曆點兩下、畫面上的日期文字都問 Core 的 `NewEventRules`、`EventText`；
/// 寫進系統行事曆交給 `EventStore` 的 `addEvent`、`updateEvent`、`deleteEvent`。
/// 版面照使用者給的原型：標題、類別、一張「開始／結束」的卡（各有日期與時間，點了在卡裡展開月曆或滾輪）、
/// 整日、行事曆，其餘是一顆一顆「+ 什麼」的膠囊，點了才長出那一格。
/// 表單改不了的行程（唯讀的行事曆）由月曆那邊改開系統的編輯畫面（`EventEditor`）。
struct NewEventScreen: View {
    @Environment(AppModel.self) private var app

    /// 月曆照哪個時區、一週從哪天開始，這裡就照一樣的
    let calendar: Calendar
    let close: () -> Void
    /// 正在改的那一筆；nil 是新增
    private let editing: EKEvent?
    /// 原本的提醒、重複規則表單表示不了，沒去動就照原本的留著
    private let keepsOtherReminder: Bool
    private let keepsOtherRepeat: Bool

    @State private var draft: NewEventDraft
    /// 打開時的樣子。跟它不一樣就是使用者動過了，取消前要先問。
    @State private var pristine: NewEventDraft
    /// 月曆現在翻到哪個月
    @State private var shownMonth: Date
    /// 「開始／結束」那張卡正在調哪一格；nil 是收著
    @State private var picking: WhenPart?
    /// 月曆上面的「2026年11月」點開了沒：點開是年、月兩個滾輪，用來一次跳很遠
    @State private var pickingYearMonth = false
    @State private var pickingCalendar = false
    @State private var showLocation = false
    @State private var showNotes = false
    @State private var problem: String?
    @State private var confirmDiscard = false
    /// 存好、而且要分享時，換成「已加進行事曆」那一頁
    @State private var saved: SavedEvent?
    /// 重複的行程：存檔前問只改這一次還是連之後的；刪除前問要不要刪
    @State private var askSaveSpan = false
    @State private var askDelete = false
    @State private var showSystemEditor = false
    /// 使用者在這一頁動過「倒數」那一顆之後想要的樣子；nil 是沒動過，照原本的
    @State private var wantsCountdown: Bool?
    @FocusState private var focus: Field?

    enum TimeField { case start, end }
    enum WhenPart { case startDay, startTime, endDay, endTime }
    enum Field { case title, location, notes }

    /// 標題那一格的高度、滾輪的高度
    private let titleHeight: CGFloat = 64
    private let wheelHeight: CGFloat = 150
    /// 地點、備註那一格長出來花多久；長出來之後等多久再捲過去
    private let fieldAnimation: Double = 0.2
    private let fieldSettleDelay: Double = 0.3
    /// 年份滾輪從今年往前、往後各列幾年
    private let yearsBack = 10
    private let yearsAhead = 20

    init(day: Date, calendar: Calendar, close: @escaping () -> Void) {
        let first = NewEventRules.initialDraft(day: day, now: Date(), calendar: calendar)
        _draft = State(initialValue: first)
        _pristine = State(initialValue: first)
        _shownMonth = State(initialValue: first.day)
        self.calendar = calendar
        self.close = close
        self.editing = nil
        self.keepsOtherReminder = false
        self.keepsOtherRepeat = false
    }

    /// 編輯既有的行程
    init(seed: EventStore.EditSeed, calendar: Calendar, close: @escaping () -> Void) {
        _draft = State(initialValue: seed.draft)
        _pristine = State(initialValue: seed.draft)
        _shownMonth = State(initialValue: seed.draft.rangeStart ?? seed.draft.day)
        self.calendar = calendar
        self.close = close
        self.editing = seed.event
        self.keepsOtherReminder = seed.keepsOtherReminder
        self.keepsOtherRepeat = seed.keepsOtherRepeat
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

    private var isDirty: Bool { draft != pristine || wantsCountdown != nil }

    /// 這一筆原本是不是倒數日（新增的一定不是）
    private var savedCountdown: Bool {
        guard let id = editing?.eventIdentifier else { return false }
        return app.settings.value.countdowns.contains(id)
    }

    /// 「倒數」那一顆現在亮不亮
    private var isCountdown: Bool { wantsCountdown ?? savedCountdown }

    /// 點「倒數」。沒買的人放滿之後加不進去，直接說原因，不要等存檔才發現。
    private func toggleCountdown() {
        let next = !isCountdown
        if next, !savedCountdown, !app.settings.canAddCountdown {
            problem = "免費版最多放 \(FullVersionAccess.freeCountdownLimit) 個倒數日，解鎖完整版就不限數量。"
            return
        }
        problem = nil
        wantsCountdown = next == savedCountdown ? nil : next
    }

    /// 存好之後把「倒數」那一顆寫進設定。新增的行程要存好才有識別碼，所以放在存檔之後。
    private func applyCountdown(to event: EKEvent) {
        guard let want = wantsCountdown, let id = event.eventIdentifier else { return }
        if app.settings.value.countdowns.contains(id) != want {
            _ = app.settings.toggleCountdown(id)
        }
    }

    private var canSave: Bool {
        !draft.cleanTitle.isEmpty
            && draft.calendarID != nil
            && NewEventRules.resolve(draft, calendar: calendar) != nil
            && NewEventRules.hasValidTime(draft)
    }

    /// 有加入蒜日子、寫得進去、不是節日的行事曆，照顯示順序。
    /// 編輯時那一筆原本在的那一本一定要在裡面，不然會顯示成沒有行事曆可以存。
    private var writableCalendars: [EKCalendar] {
        let holidays = app.settings.value.holidayCalendarIDs
        var list = app.vm.shownCalendars.filter {
            $0.allowsContentModifications && !holidays.contains($0.calendarIdentifier)
        }
        if let home = editing?.calendar, home.allowsContentModifications,
           !list.contains(where: { $0.calendarIdentifier == home.calendarIdentifier }) {
            list.append(home)
        }
        return list
    }

    private var selectedCalendar: EKCalendar? {
        writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
    }

    private func setUp() {
        guard editing == nil, draft.calendarID == nil else { return }
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
        if let editing {
            guard isDirty else {
                close()
                return
            }
            // 只動了「倒數」：行程本身不用重存，也就不用問重複的範圍
            if draft == pristine {
                applyCountdown(to: editing)
                close()
                return
            }
            // 重複的行程先問範圍。動了重複規則的話只能連之後的一起改，就不問了。
            if editing.hasRecurrenceRules, draft.repeats == pristine.repeats {
                askSaveSpan = true
            } else {
                saveEdit(editing, time: time, allFuture: editing.hasRecurrenceRules)
            }
            return
        }
        let result = app.store.addEvent(draft, time: time)
        guard let event = result.event else {
            problem = result.problem ?? "沒有存成功，請再試一次。"
            return
        }
        app.settings.update { $0.lastEventCalendarID = draft.calendarID }
        finish(event, time: time, headline: "已加進行事曆")
    }

    private func saveEdit(_ event: EKEvent, time: ResolvedEventTime, allFuture: Bool) {
        if let failure = app.store.updateEvent(event, from: pristine, to: draft, time: time, allFuture: allFuture) {
            problem = failure
            return
        }
        finish(event, time: time, headline: "已儲存")
    }

    /// 存好之後：記下使用者替這一筆選的類別，然後關掉，或換成分享那一頁
    private func finish(_ event: EKEvent, time: ResolvedEventTime, headline: String) {
        problem = nil
        if let chosen = draft.categoryID, chosen != pristine.categoryID, let id = event.eventIdentifier {
            app.settings.update { $0.eventCategory[id] = chosen }
        }
        applyCountdown(to: event)
        guard draft.wantsShare else {
            close()
            return
        }
        focus = nil
        saved = SavedEvent(
            draft: draft,
            time: time,
            event: event,
            headline: headline,
            calendarLine: selectedCalendar.map(calendarLine) ?? "",
            dotColor: app.vm.color(NewEventRules.shownCategoryID(draft, settings: app.settings.value))
        )
    }

    private func delete(_ event: EKEvent, allFuture: Bool) {
        if let failure = app.store.deleteEvent(event, allFuture: allFuture) {
            problem = failure
            return
        }
        close()
    }

    // MARK: 表單

    private var form: some View {
        ScrollViewReader { proxy in
            formScroll
                .onChange(of: focus) { _, field in
                    guard let field, field != .title else { return }
                    // 那一格剛長出來、鍵盤也還在升。等排好再捲，不然它會停在鍵盤後面看不到。
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(fieldSettleDelay))
                        withAnimation(.easeOut(duration: fieldAnimation)) {
                            proxy.scrollTo(field, anchor: .bottom)
                        }
                    }
                }
        }
    }

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                titleField
                categorySection
                whenCard
                optionsSection
                if let editing { editFooter(editing) }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s2)
            .padding(.bottom, DT.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .onAppear { setUp() }
        .confirmationDialog("放棄這筆行程？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放棄", role: .destructive) { close() }
            Button("繼續編輯", role: .cancel) {}
        }
    }

    /// 上面那一列：左邊取消、中間標題、右邊打勾就是儲存。儲存放上面，鍵盤開著也按得到，下面也不用再佔一條。
    private var topBar: some View {
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            ZStack {
                Text(editing == nil ? "新增行程" : "編輯行程")
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
                    saveButton
                }
            }
            if let problem {
                Text(problem)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.destructive)
            }
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.top, DT.Space.s3)
        .padding(.bottom, DT.Space.s1)
        .background(Theme.bg)
    }

    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: DT.Size.touch, height: DT.Size.touch)
                .background(Circle().fill(Theme.accent))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.4)
        .accessibilityLabel(draft.wantsShare ? "儲存並分享" : "儲存")
        .confirmationDialog("這是重複的行程", isPresented: $askSaveSpan, titleVisibility: .visible) {
            Button("只改這一次") { commitEdit(allFuture: false) }
            Button("這次和之後的都改") { commitEdit(allFuture: true) }
            Button("繼續編輯", role: .cancel) {}
        }
    }

    private func commitEdit(allFuture: Bool) {
        guard let editing, let time = NewEventRules.resolve(draft, calendar: calendar) else { return }
        saveEdit(editing, time: time, allFuture: allFuture)
    }

    // MARK: 編輯時最下面：刪除、改開系統的畫面

    private func editFooter(_ event: EKEvent) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            Button {
                askDelete = true
            } label: {
                Text("刪除行程")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row)
                    .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .confirmationDialog(
                event.hasRecurrenceRules ? "這是重複的行程" : "刪除這筆行程？",
                isPresented: $askDelete,
                titleVisibility: .visible
            ) {
                if event.hasRecurrenceRules {
                    Button("只刪這一次", role: .destructive) { delete(event, allFuture: false) }
                    Button("這次和之後的都刪", role: .destructive) { delete(event, allFuture: true) }
                } else {
                    Button("刪除", role: .destructive) { delete(event, allFuture: false) }
                }
                Button("不刪", role: .cancel) {}
            }
            Button {
                showSystemEditor = true
            } label: {
                Text("邀請對象、網址這些欄位，改用 iPhone 內建的畫面編輯")
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                    .underline()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
                    .padding(.horizontal, DT.Space.s1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .sheet(isPresented: $showSystemEditor) {
                // 內建畫面存完，這張表單上的內容就是舊的了，所以一起關掉
                EventEditor(store: app.store, event: event, defaultDay: draft.day, calendar: calendar) {
                    showSystemEditor = false
                    close()
                }
                .ignoresSafeArea()
            }
        }
        .padding(.top, DT.Space.s2)
    }

    // MARK: 類別

    /// 每一筆行程自己選類別。沒選的時候標的是存下去會歸到的那一類（行事曆的預設，或標題對到的關鍵字規則）。
    private var categorySection: some View {
        let settings = app.settings.value
        let shown = NewEventRules.shownCategoryID(draft, settings: settings)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DT.Space.s2) {
                ForEach(settings.categories) { category in
                    categoryChip(category, isOn: category.id == shown)
                }
            }
        }
        .accessibilityLabel("類別")
    }

    private func categoryChip(_ category: EventCategory, isOn: Bool) -> some View {
        Button {
            draft.categoryID = category.id
        } label: {
            HStack(spacing: DT.Space.s2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(app.vm.color(category.id))
                    .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                Text(category.name)
                    .dFont(DT.TypeScale.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Theme.strong : Theme.ink)
            .padding(.horizontal, DT.Space.s4)
            .frame(minHeight: DT.Size.touch)
            .background(Capsule().fill(isOn ? Theme.soft : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: isOn ? 1.5 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
            .background(Capsule().fill(isOn ? Theme.accent : Theme.bg))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 開始、結束

    /// 開始與結束各一欄：上面日期、下面時間。點哪一格，卡裡就展開那一格的月曆或滾輪。下面接「整日」和行事曆。
    private var whenCard: some View {
        let allDay = NewEventRules.isAllDay(draft)
        let isWrong = !NewEventRules.hasValidTime(draft)
        let endDay = NewEventRules.endDay(draft, calendar: calendar)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DT.Space.s1) {
                whenColumn("開始") {
                    whenButton(
                        EventText.shortDay(NewEventRules.startDay(draft), calendar: calendar),
                        part: .startDay, label: "開始日期"
                    )
                    if !allDay {
                        whenButton(EventText.clock24(draft.startMinutes), part: .startTime, label: "開始時間", isBig: true)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
                whenColumn("結束") {
                    whenButton(EventText.shortDay(endDay, calendar: calendar), part: .endDay, label: "結束日期", isWrong: isWrong)
                    if !allDay {
                        whenButton(
                            EventText.clock24(NewEventRules.endClock(draft, calendar: calendar)),
                            part: .endTime, label: "結束時間", isBig: true, isWrong: isWrong
                        )
                    }
                }
            }
            .padding(DT.Space.s2)
            if isWrong {
                Text("結束比開始早，改一下才能存。")
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DT.Space.s4)
                    .padding(.bottom, DT.Space.s2)
            }
            if let part = picking {
                whenPicker(part)
                    .padding(.horizontal, DT.Space.s2)
                    .padding(.bottom, DT.Space.s2)
            }
            Hairline()
            Toggle(isOn: allDayBinding) {
                Text("整日")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
            .padding(.horizontal, DT.Space.s4)
            .frame(minHeight: DT.Size.row)
            Hairline()
            calendarSection
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { NewEventRules.isAllDay(draft) },
            set: { isOn in
                draft = NewEventRules.settingAllDay(isOn, in: draft, calendar: calendar)
                // 整日沒有鐘點可以調，正開著滾輪就收起來
                if isOn, picking == .startTime || picking == .endTime {
                    picking = nil
                }
            }
        )
    }

    private func whenColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            Text(title)
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
                .padding(.leading, DT.Space.s1)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    /// 卡上的一格：日期或時間。正在調的那一格有主色外框；起訖顛倒時結束那兩格劃掉。
    private func whenButton(
        _ text: String, part: WhenPart, label: String, isBig: Bool = false, isWrong: Bool = false
    ) -> some View {
        let isOn = picking == part
        return Button {
            togglePicking(part)
        } label: {
            Text(text)
                .strikethrough(isWrong)
                .dFont(isBig ? DT.TypeScale.title3 : DT.TypeScale.callout)
                .foregroundStyle(isWrong ? Theme.destructive : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, DT.Space.s3)
                .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(Theme.bg))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md)
                        .strokeBorder(Theme.accent, lineWidth: isOn ? 2 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label) \(text)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func togglePicking(_ part: WhenPart) {
        if picking == part {
            picking = nil
            return
        }
        // 月曆、滾輪要有地方長出來，先把鍵盤收掉
        focus = nil
        pickingCalendar = false
        pickingYearMonth = false
        shownMonth = part == .endDay
            ? NewEventRules.endDay(draft, calendar: calendar)
            : NewEventRules.startDay(draft)
        picking = part
    }

    private func whenPicker(_ part: WhenPart) -> some View {
        VStack(spacing: DT.Space.s2) {
            switch part {
            case .startDay:
                monthGrid(isEnd: false)
            case .endDay:
                monthGrid(isEnd: true)
            case .startTime:
                wheels(.start)
                durationRow
            case .endTime:
                wheels(.end)
                durationRow
            }
            HStack {
                Text(pickerHint(part))
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                Spacer()
                Button {
                    picking = nil
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

    private func pickerHint(_ part: WhenPart) -> String {
        switch part {
        case .startDay: return "結束那一天會跟著移"
        case .endDay: return "開始那一天之前的不能選"
        case .startTime: return "結束時間會跟著往後移"
        case .endTime:
            return NewEventRules.hasValidTime(draft) ? "共 " + EventText.duration(draft.durationMinutes) : ""
        }
    }

    /// 直接點一種長度：結束改成開始之後那麼久
    private var durationRow: some View {
        HStack(spacing: DT.Space.s2) {
            ForEach(NewEventRules.durationChoices, id: \.self) { minutes in
                chip(EventText.duration(minutes), isOn: draft.durationMinutes == minutes) {
                    draft = NewEventRules.settingDuration(minutes, in: draft)
                }
            }
        }
    }

    /// 兩個滾輪：幾點（0 到 23）、幾分（0 到 59）。系統的時間滾輪會帶「上午、下午」這些字，所以自己排。
    private func wheels(_ field: TimeField) -> some View {
        let minutes = field == .start ? draft.startMinutes : NewEventRules.endClock(draft, calendar: calendar)
        let hour = Binding<Int>(
            get: { minutes / 60 },
            set: { setClock(field, hour: $0, minute: minutes % 60) }
        )
        let minute = Binding<Int>(
            get: { minutes % 60 },
            set: { setClock(field, hour: minutes / 60, minute: $0) }
        )
        return HStack(spacing: 0) {
            Picker("幾點", selection: hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(verbatim: "\(value)").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            Text(verbatim: ":")
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Picker("幾分", selection: minute) {
                ForEach(minuteOptions(including: minutes % 60), id: \.self) { value in
                    Text(verbatim: value < 10 ? "0\(value)" : "\(value)").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .pickerStyle(.wheel)
        .frame(height: wheelHeight)
        .padding(.horizontal, DT.Space.s8)
    }

    /// 滾輪上的分鐘，一格跳多少看 `NewEventRules.minuteStep`。現在的分鐘數不在格子上就補進去，不然滾輪會沒有選到的那一列。
    private func minuteOptions(including current: Int) -> [Int] {
        var options = Array(stride(from: 0, to: 60, by: NewEventRules.minuteStep))
        if !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    private func setClock(_ field: TimeField, hour: Int, minute: Int) {
        let total = hour * 60 + minute
        switch field {
        case .start: draft = NewEventRules.settingStart(total, in: draft)
        case .end: draft = NewEventRules.settingEndClock(total, in: draft, calendar: calendar)
        }
    }

    // MARK: 月曆（選開始或結束的那一天）

    private enum CellRole { case plain, edge, between }

    /// 開始、結束那兩天是實心，中間的是淡色
    private func role(of day: Date) -> CellRole {
        let start = NewEventRules.startDay(draft)
        let end = NewEventRules.endDay(draft, calendar: calendar)
        if day == start || day == end { return .edge }
        if day > start, day < end { return .between }
        return .plain
    }

    private func monthGrid(isEnd: Bool) -> some View {
        let cells = NewEventRules.monthCells(month: shownMonth, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(spacing: DT.Space.s2) {
            HStack(spacing: 0) {
                Button {
                    pickingYearMonth.toggle()
                } label: {
                    HStack(spacing: DT.Space.s1) {
                        Text(EventText.month(shownMonth, calendar: calendar))
                            .dFont(DT.TypeScale.headline)
                        Image(systemName: pickingYearMonth ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(pickingYearMonth ? Theme.strong : Theme.ink)
                    .frame(minHeight: DT.Size.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("選年份和月份，現在是\(EventText.month(shownMonth, calendar: calendar))")
                .accessibilityAddTraits(pickingYearMonth ? .isSelected : [])
                Spacer()
                if !pickingYearMonth {
                    monthArrow("chevron.left", label: "上個月", months: -1)
                    monthArrow("chevron.right", label: "下個月", months: 1)
                }
            }
            if pickingYearMonth {
                yearMonthWheels
            } else {
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
                            dayCell(cell, isEnd: isEnd)
                        } else {
                            Color.clear.frame(height: DT.Size.touch)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DT.Space.s1)
    }

    /// 年、月兩個滾輪：只是把月曆翻到那個月，選哪一天還是回月曆點。再點一次上面的年月就回到月曆。
    private var yearMonthWheels: some View {
        let parts = calendar.dateComponents([.year, .month], from: shownMonth)
        let thisYear = calendar.component(.year, from: app.vm.today)
        let shownYear = parts.year ?? thisYear
        let shownMonthNumber = parts.month ?? 1
        // 正在看的那一年不在範圍裡（編輯很久以前或很久以後的行程）就把範圍拉過去
        let firstYear = min(thisYear - yearsBack, shownYear)
        let lastYear = max(thisYear + yearsAhead, shownYear)
        let year = Binding<Int>(
            get: { shownYear },
            set: { showMonth(year: $0, month: shownMonthNumber) }
        )
        let month = Binding<Int>(
            get: { shownMonthNumber },
            set: { showMonth(year: shownYear, month: $0) }
        )
        return HStack(spacing: 0) {
            Picker("年份", selection: year) {
                ForEach(firstYear...lastYear, id: \.self) { value in
                    Text(verbatim: "\(value)年").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("月份", selection: month) {
                ForEach(1...12, id: \.self) { value in
                    Text(verbatim: "\(value)月").tag(value)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .pickerStyle(.wheel)
        .frame(height: wheelHeight)
    }

    private func showMonth(year: Int, month: Int) {
        if let next = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            shownMonth = next
        }
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

    private func dayCell(_ day: Date, isEnd: Bool) -> some View {
        let cellRole = role(of: day)
        // 選結束那一天時，開始之前的不能點
        let isOff = isEnd && day < NewEventRules.startDay(draft)
        let fill: Color
        switch cellRole {
        case .edge: fill = Theme.accent
        case .between: fill = Theme.soft
        case .plain: fill = Color.clear
        }
        let textColor: Color = cellRole == .edge ? Theme.onAccent : (isOff ? Theme.tertiary : Theme.ink)
        return Button {
            draft = isEnd
                ? NewEventRules.settingEndDay(day, in: draft, calendar: calendar)
                : NewEventRules.settingStartDay(day, in: draft, calendar: calendar)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .dFont(DT.TypeScale.callout)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                .background(
                    RoundedRectangle(cornerRadius: cellRole == .edge ? DT.Radius.pill : 0).fill(fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(isOff)
        .accessibilityLabel(EventText.day(day, calendar: calendar))
        .accessibilityAddTraits(cellRole == .plain ? [] : .isSelected)
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
                if pickingCalendar { picking = nil }
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

    // MARK: 六顆選項的膠囊

    /// 選項的樣子：虛線框寫「+ 什麼」是還沒設；設了變實心，有內容的直接寫內容（「30 分鐘前」「每週」）
    private func optionLabel(_ title: String, systemImage: String, isSet: Bool, value: String? = nil) -> some View {
        HStack(spacing: DT.Space.s1) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(value ?? (isSet ? title : "+ " + title))
                .dFont(DT.TypeScale.subheadline)
                .lineLimit(1)
        }
        .foregroundStyle(isSet ? Theme.strong : Theme.sub)
        .padding(.horizontal, DT.Space.s3)
        .frame(minHeight: DT.Size.touch)
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
            WrapRow(spacing: DT.Space.s2) {
                Menu {
                    Button("不提醒") { draft.reminder = nil }
                    ForEach(reminders, id: \.self) { option in
                        Button(option.label) { draft.reminder = option }
                    }
                } label: {
                    optionLabel("提醒", systemImage: "bell", isSet: draft.reminder != nil, value: draft.reminder?.label)
                }
                // 選單不指定樣式的話，系統會自己套一層灰底，把裡面的字擠成刪節號
                .buttonStyle(.plain)
                .accessibilityLabel("提醒")
                .accessibilityValue(draft.reminder?.label ?? "不提醒")
                Menu {
                    Button("不重複") { draft.repeats = nil }
                    ForEach(EventRepeat.allCases, id: \.self) { option in
                        Button(option.label) { draft.repeats = option }
                    }
                } label: {
                    optionLabel("重複", systemImage: "repeat", isSet: draft.repeats != nil, value: draft.repeats?.label)
                }
                .buttonStyle(.plain)
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
                Button {
                    toggleCountdown()
                } label: {
                    optionLabel("倒數日", systemImage: "hourglass", isSet: isCountdown)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("加入倒數日")
                .accessibilityAddTraits(isCountdown ? .isSelected : [])
            }
            if hasLocation || hasNotes || keptReminderNote != nil || keptRepeatNote != nil {
                optionDetails(hasLocation: hasLocation, hasNotes: hasNotes)
            }
        }
    }

    /// 點「地點」「備註」：還沒打開就打開並把游標放進去；開著而且是空的就收起來
    private func toggleField(_ field: Field) {
        switch field {
        case .location:
            if showLocation, draft.location.isEmpty {
                withAnimation(.easeOut(duration: fieldAnimation)) { showLocation = false }
                if focus == .location { focus = nil }
                return
            }
            withAnimation(.easeOut(duration: fieldAnimation)) { showLocation = true }
        case .notes:
            if showNotes, draft.notes.isEmpty {
                withAnimation(.easeOut(duration: fieldAnimation)) { showNotes = false }
                if focus == .notes { focus = nil }
                return
            }
            withAnimation(.easeOut(duration: fieldAnimation)) { showNotes = true }
        case .title:
            break
        }
        // 同一刻就把游標放進去的話，那一格還不在畫面上，游標會放不進去或跳一下
        DispatchQueue.main.async { focus = field }
    }

    /// 原本的提醒、重複規則表單上沒有對應的選項時，寫一行讓人知道它還在。在選單選了別的就會換掉。
    private var keptReminderNote: String? {
        keepsOtherReminder && draft.reminder == nil ? "原本的提醒照舊" : nil
    }

    private var keptRepeatNote: String? {
        keepsOtherRepeat && draft.repeats == nil ? "原本的重複規則照舊" : nil
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
            if let keptReminderNote {
                detailRow("bell", keptReminderNote)
            }
            if let keptRepeatNote {
                detailRow("repeat", keptRepeatNote)
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
                .id(Field.location)
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
                .id(Field.notes)
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
    /// 最上面那一句：「已加進行事曆」或「已儲存」
    let headline: String
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
                    Text(saved.headline)
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
