import SwiftUI
import MapKit
import UIKit
import EventKit
import StoreKit
import CalendarCore

/// 蒜日子自己的新增與編輯行程畫面（規格第 20 節）。
/// 帶入什麼、起訖怎麼推、月曆點兩下、畫面上的日期文字都問 Core 的 `NewEventRules`、`EventText`；
/// 寫進系統行事曆交給 `EventStore` 的 `addEvent`、`updateEvent`、`deleteEvent`。
/// 版面：標題、類別、一張「開始／結束」的卡（上下兩列，各有含年份的日期與時間，點了在卡裡展開月曆或滾輪）、
/// 整日、行事曆，下面一張卡直列排提醒、重複、地點、備註、分享、倒數日。
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
    @State private var problem: String?
    @State private var confirmDiscard = false
    /// 備註的記事本開著
    @State private var editingNotes = false
    /// 找地點的那一頁開著
    @State private var editingPlace = false
    /// 地點的地圖建議
    @State private var placeSearch = PlaceSearch()
    /// 存好、而且要分享時，換成「已加進行事曆」那一頁
    @State private var saved: SavedEvent?
    /// 重複的行程：存檔前問只改這一次還是連之後的；刪除前問要不要刪
    @State private var askSaveSpan = false
    @State private var askDelete = false
    /// 使用者在這一頁動過「倒數」那一顆之後想要的樣子；nil 是沒動過，照原本的
    @State private var wantsCountdown: Bool?
    @FocusState private var focus: Field?
    @Environment(\.requestReview) private var requestReview

    enum TimeField { case start, end }
    enum WhenPart { case startDay, startTime, endDay, endTime }
    enum Field { case title, location }

    /// 標題那一格的高度、滾輪的高度
    private let titleHeight: CGFloat = 64
    private let wheelHeight: CGFloat = 150
    /// 存好之後等表單收下去、回到月曆，再請 iOS 跳評分視窗
    private let reviewDelay: Double = 0.6
    /// 地點、備註那一格長出來之後等多久再捲過去
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
        // 上面跳出紅字（存不了、刪不掉、倒數日放滿）時震一下
        .sensoryFeedback(.error, trigger: problem) { _, now in now != nil }
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
        app.settings.update { $0.savedEventCount += 1 }
        // 要分享的人正忙著傳給別人，不在這時候問
        guard draft.wantsShare else {
            let version = VeggieConfig.current.shortVersion
            let asksReview = ReviewTiming.shouldAsk(app.settings.value, version: version, now: Date())
            if asksReview {
                app.settings.update { $0.reviewAskedVersion = version }
            }
            close()
            if asksReview { askReviewAfterClosing() }
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

    /// 不等的話評分視窗會疊在正在收下去的表單上
    private func askReviewAfterClosing() {
        let ask = requestReview
        let delay = reviewDelay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            ask()
        }
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
                        withAnimation(Theme.Motion.change) {
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
            // 月曆、滾輪、行事曆清單開合時，下面的欄位用滑的讓位
            .animation(Theme.Motion.change, value: picking)
            .animation(Theme.Motion.change, value: pickingYearMonth)
            .animation(Theme.Motion.change, value: pickingCalendar)
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
        // 紅字出現、消失時，下面的表單用滑的讓位，不要跳一下
        .animation(Theme.Motion.change, value: problem)
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

    // MARK: 編輯時最下面：刪除

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

    /// 開始與結束各一欄：上面日期（年份小字在日期上面）、下面時間。點哪一格，卡裡就展開那一格的月曆或滾輪。
    /// 下面接「整日」「重複」和行事曆。
    private var whenCard: some View {
        let allDay = NewEventRules.isAllDay(draft)
        let isWrong = !NewEventRules.hasValidTime(draft)
        let startDay = NewEventRules.startDay(draft)
        let endDay = NewEventRules.endDay(draft, calendar: calendar)
        let repeatText = draft.repeats?.label ?? keptRepeatNote ?? "不重複"
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DT.Space.s1) {
                whenColumn("開始") {
                    whenButton(
                        EventText.shortDay(startDay, calendar: calendar), caption: EventText.year(startDay, calendar: calendar),
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
                    whenButton(
                        EventText.shortDay(endDay, calendar: calendar), caption: EventText.year(endDay, calendar: calendar),
                        part: .endDay, label: "結束日期", isWrong: isWrong
                    )
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
            unfolding {
                if let part = picking {
                    whenPicker(part)
                        .padding(.horizontal, DT.Space.s2)
                        .padding(.bottom, DT.Space.s2)
                }
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
            Menu {
                Button("不重複") { draft.repeats = nil }
                ForEach(EventRepeat.allCases, id: \.self) { option in
                    Button(option.label) { draft.repeats = option }
                }
            } label: {
                menuRow("重複", value: repeatText)
                    .padding(.horizontal, DT.Space.s4)
            }
            // 選單不指定樣式的話，系統會自己套一層灰底
            .buttonStyle(.plain)
            .accessibilityLabel("重複")
            .accessibilityValue(repeatText)
            Hairline()
            calendarSection
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
    }

    /// 開合的那一塊：框從上面往下長，裡面的東西跟著露出來，不會蓋到下面的欄位
    private func unfolding<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .top)
            .clipped()
            // 剛長出來的東西跟著整塊一起移，不然它會先出現在最後的位置，跟還在滑的那一列疊在一起
            .geometryGroup()
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
        _ text: String, caption: String? = nil, part: WhenPart, label: String,
        isBig: Bool = false, isWrong: Bool = false
    ) -> some View {
        let isOn = picking == part
        return Button {
            togglePicking(part)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // 年份用小字放在日期上面，左右兩欄才放得下
                if let caption {
                    Text(caption)
                        .dFont(DT.TypeScale.caption)
                        .foregroundStyle(Theme.sub)
                }
                Text(text)
                    .strikethrough(isWrong)
                    .dFont(isBig ? DT.TypeScale.title3 : DT.TypeScale.callout)
                    .foregroundStyle(isWrong ? Theme.destructive : Theme.ink)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, DT.Space.s3)
            .padding(.vertical, caption == nil ? 0 : DT.Space.s1)
            .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(Theme.bg))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.md)
                        .strokeBorder(Theme.accent, lineWidth: isOn ? 2 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label) \(caption ?? "")\(text)")
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
    /// 兩個都是循環的：23 下面是 0，59 下面是 00。
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
            LoopWheel(label: "幾點", values: Array(0..<24), selection: hour) { "\($0)" }
                .frame(maxWidth: .infinity)
                .clipped()
            Text(verbatim: ":")
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            LoopWheel(label: "幾分", values: minuteOptions(including: minutes % 60), selection: minute) {
                $0 < 10 ? "0\($0)" : "\($0)"
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
            unfolding {
                if pickingCalendar { calendarList }
            }
        }
        .padding(.horizontal, DT.Space.s4)
        .frame(maxWidth: .infinity)
        .geometryGroup()
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

    // MARK: 其他選項
    /// 提醒、地點、備註、分享、倒數日，照設定頁的樣子一列一列排在同一張卡裡（重複放在上面「整日」底下）
    private var optionsSection: some View {
        let reminders = draft.kind == .timed ? EventReminder.timedCases : EventReminder.allDayCases
        let reminderText = draft.reminder?.label ?? keptReminderNote ?? "不提醒"
        let notesPreview = draft.notes
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return SectionCard {
            Menu {
                Button("不提醒") { draft.reminder = nil }
                ForEach(reminders, id: \.self) { option in
                    Button(option.label) { draft.reminder = option }
                }
            } label: {
                menuRow("提醒", icon: "bell", value: reminderText)
            }
            // 選單不指定樣式的話，系統會自己套一層灰底
            .buttonStyle(.plain)
            .accessibilityLabel("提醒")
            .accessibilityValue(reminderText)
            Hairline()
            locationRow
                .id(Field.location)
            Hairline()
            // 備註常常很長，點了開一張整頁的記事本來打
            Button {
                editingNotes = true
            } label: {
                HStack(spacing: DT.Space.s3) {
                    VeggieRowIcon(systemName: "text.alignleft")
                    Text("備註")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                    Text(notesPreview.isEmpty ? "未填" : notesPreview)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: DT.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("備註")
            .accessibilityValue(draft.notes.isEmpty ? "未填" : draft.notes)
            .sheet(isPresented: $editingNotes) {
                NotesEditorSheet(notes: $draft.notes)
            }
            Hairline()
            SettingsRow(label: "存好後分享", icon: "square.and.arrow.up") {
                Toggle("存好後分享", isOn: $draft.wantsShare)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            Hairline()
            SettingsRow(label: "加入倒數日", icon: "hourglass") {
                Toggle("加入倒數日", isOn: Binding(get: { isCountdown }, set: { on in
                    if on != isCountdown { toggleCountdown() }
                }))
                .labelsHidden()
                .tint(Theme.accent)
            }
        }
    }

    // MARK: 地點

    /// 地點：跟備註一樣，點了開一整頁來找（`PlacePickerSheet`）。
    /// 沒填寫「未填」；選了地圖上的地方，名稱下面寫地址，再附一張小地圖。
    @ViewBuilder
    private var locationRow: some View {
        HStack(spacing: DT.Space.s3) {
            Button {
                editingPlace = true
            } label: {
                HStack(spacing: DT.Space.s3) {
                    VeggieRowIcon(systemName: "mappin.and.ellipse")
                    if draft.location.isEmpty {
                        Text("地點")
                            .dFont(DT.TypeScale.body)
                            .foregroundStyle(Theme.ink)
                        Text("未填")
                            .dFont(DT.TypeScale.body)
                            .foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.sub)
                            .accessibilityHidden(true)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.location)
                                .dFont(DT.TypeScale.body)
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            if let place = draft.place, !place.address.isEmpty {
                                Text(place.address)
                                    .dFont(DT.TypeScale.footnote)
                                    .foregroundStyle(Theme.sub)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, draft.location.isEmpty ? 0 : DT.Space.s2)
                .frame(minHeight: DT.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("地點")
            .accessibilityValue(draft.location.isEmpty ? "未填" : draft.location)
            if !draft.location.isEmpty {
                Button {
                    draft.location = ""
                    draft.place = nil
                    placeSearch.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: DT.Size.touch, height: DT.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除地點")
            }
        }
        .sheet(isPresented: $editingPlace) {
            PlacePickerSheet(text: locationText, search: placeSearch) { result in
                editingPlace = false
                pick(result)
            }
        }
        if let place = draft.place {
            PlaceMapPreview(place: place)
                .padding(.leading, DT.Space.s6 + DT.Space.s3)
                .padding(.bottom, DT.Space.s3)
        }
    }

    /// 地點欄的字。改了字就不再是選到的那個地方，座標拿掉、重新找建議。
    private var locationText: Binding<String> {
        Binding(
            get: { draft.location },
            set: { text in
                guard text != draft.location else { return }
                draft.location = text
                draft.place = nil
                placeSearch.update(text)
            }
        )
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        draft.location = result.title
        placeSearch.clear()
        focus = nil
        Task {
            // 查不到座標就只留字
            if let point = await placeSearch.resolve(result), draft.location == result.title {
                draft.place = point
            }
        }
    }

    /// 點了會跳選單的一列：右邊是目前選的，加上下箭頭
    private func menuRow(_ title: String, icon: String? = nil, value: String) -> some View {
        HStack(spacing: DT.Space.s3) {
            if let icon { VeggieRowIcon(systemName: icon) }
            Text(title)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .accessibilityHidden(true)
        }
        .frame(minHeight: DT.Size.row)
        .contentShape(Rectangle())
    }

    /// 原本的提醒、重複規則表單上沒有對應的選項時，讓人知道它還在。在選單選了別的就會換掉。
    private var keptReminderNote: String? {
        keepsOtherReminder && draft.reminder == nil ? "原本的照舊" : nil
    }

    private var keptRepeatNote: String? {
        keepsOtherRepeat && draft.repeats == nil ? "原本的照舊" : nil
    }
}

/// 選了地圖上的地點之後，下面那張小地圖。點了用「地圖」app 打開。
struct PlaceMapPreview: View {
    let place: PlacePoint

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = place.name
            item.openInMaps()
        } label: {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600
            ))) {
                Marker(place.name, coordinate: coordinate)
            }
            .allowsHitTesting(false)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("在地圖打開 \(place.name)")
    }
}

/// 找地點的那一頁：打開游標就在搜尋欄，下面列 Apple 地圖的建議。選一個就回表單。
/// 找不到的話照打的字存：按「完成」收起來，地點就是打的那幾個字。
struct PlacePickerSheet: View {
    @Binding var text: String
    let search: PlaceSearch
    let pick: (MKLocalSearchCompletion) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s3) {
            ZStack {
                Text("地點")
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
            }
            HStack(spacing: DT.Space.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
                TextField("地名或地址", text: $text)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { dismiss() }
                    .accessibilityLabel("搜尋地點")
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiary)
                            .frame(width: DT.Size.touch, height: DT.Size.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, DT.Space.s3)
            .frame(minHeight: DT.Size.touch)
            .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(Theme.card))
            ScrollView {
                if !search.results.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(search.results.enumerated()), id: \.offset) { index, result in
                            if index > 0 { Hairline() }
                            Button {
                                pick(result)
                            } label: {
                                HStack(spacing: DT.Space.s3) {
                                    VeggieRowIcon(systemName: "mappin.and.ellipse")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .dFont(DT.TypeScale.body)
                                            .foregroundStyle(Theme.ink)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .dFont(DT.TypeScale.footnote)
                                                .foregroundStyle(Theme.sub)
                                        }
                                    }
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, DT.Space.s2)
                                .frame(minHeight: DT.Size.row)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("\(result.title)，\(result.subtitle)")
                        }
                    }
                    .padding(.horizontal, DT.Space.s4)
                    .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
                }
                if !text.isEmpty {
                    Text("找不到的話，按「完成」就照打的字存。")
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Space.s1)
                        .padding(.top, DT.Space.s3)
                }
            }
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.top, DT.Space.s4)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear {
            focused = true
            // 打開時已經有字（之前照打的字存的），先列一次建議
            if !text.isEmpty { search.update(text) }
        }
    }
}

/// 備註的記事本：整頁都是打字的地方，打開就有游標。改的字直接寫回表單，按「完成」收起來。
struct NotesEditorSheet: View {
    @Binding var notes: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s3) {
            ZStack {
                Text("備註")
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
            }
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("想記什麼都寫在這裡。網址照貼就好。")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, DT.Space.s4 + 5)
                        .padding(.vertical, DT.Space.s4 + 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $notes)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(DT.Space.s4)
                    .accessibilityLabel("備註")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.top, DT.Space.s4)
        .padding(.bottom, DT.Space.s2)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear { focused = true }
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
    @State private var message: String?
    @State private var messageIsProblem = false

    /// 打勾那個圓的直徑
    private let checkSize: CGFloat = 56

    struct SharePayload: Identifiable {
        let id = UUID()
        let text: String
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
            ActivityView(items: [payload.text])
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

    /// 分享出去的是一段文字：時間標題加「加到 Google 日曆」的連結（不再附 .ics 檔，LINE 會把它拆成一則要下載的檔案）
    private func share() {
        message = nil
        sharing = SharePayload(text: ShareMessage.text(saved.draft, calendar: calendar))
    }
}

/// 循環的滾輪：同一組數字重複很多輪，打開時停在中間那一輪，所以滾過最後一個會接回第一個。
/// 哪一列對到哪個數字、數字從外面被改掉時要轉去哪一列，都在 `LoopWheelRules`。
private struct LoopWheel: View {
    let label: String
    let values: [Int]
    @Binding var selection: Int
    let text: (Int) -> String

    /// 滾輪現在停在長條上的第幾列
    @State private var row: Int

    init(label: String, values: [Int], selection: Binding<Int>, text: @escaping (Int) -> String) {
        self.label = label
        self.values = values
        _selection = selection
        self.text = text
        let index = values.firstIndex(of: selection.wrappedValue) ?? 0
        _row = State(initialValue: LoopWheelRules.middleRow(index: index, count: values.count))
    }

    var body: some View {
        let count = values.count
        let rowBinding = Binding<Int>(
            get: { row },
            set: { next in
                row = next
                selection = values[LoopWheelRules.index(ofRow: next, count: count)]
            }
        )
        return Picker(label, selection: rowBinding) {
            ForEach(0..<LoopWheelRules.rowCount(count), id: \.self) { item in
                Text(verbatim: text(values[LoopWheelRules.index(ofRow: item, count: count)])).tag(item)
            }
        }
        // 數字從外面被改掉（點了「1 小時」、開始時間推著結束走）：轉到最近的那一列
        .onChange(of: selection) { _, value in
            follow(value)
        }
        // 格子的數量變了，原本的列數對不上，回中間重排
        .onChange(of: count) { _, _ in
            let index = values.firstIndex(of: selection) ?? 0
            row = LoopWheelRules.middleRow(index: index, count: values.count)
        }
    }

    private func follow(_ value: Int) {
        guard let index = values.firstIndex(of: value) else { return }
        let next = LoopWheelRules.nearestRow(toIndex: index, from: row, count: values.count)
        if next != row { row = next }
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
