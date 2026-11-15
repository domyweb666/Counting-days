import SwiftUI
import EventKit
import CalendarCore

enum SheetKind: Identifiable {
    case newEvent(Date)
    case edit(CalEvent)
    case settings
    case search
    case monthPicker

    var id: String {
        switch self {
        case .newEvent(let d): return "new\(d.timeIntervalSinceReferenceDate)"
        case .edit(let e): return "edit" + e.id
        case .settings: return "settings"
        case .search: return "search"
        case .monthPicker: return "month"
        }
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(CoachController.self) private var coach
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: SheetKind?
    @State private var shortNameTarget: CalEvent?
    @State private var shortNameText = ""
    @State private var showShortName = false

    private var vm: CalendarViewModel { app.vm }
    /// 月曆樣式（在設定裡選）
    private var mode: DisplayMode { app.settings.value.mode }

    private var actions: CalendarActions {
        CalendarActions(
            open: { sheet = .edit($0) },
            add: { sheet = .newEvent($0) },
            shortName: { event in
                shortNameTarget = event
                shortNameText = app.settings.value.shortNames[event.seriesID] ?? ""
                showShortName = true
            }
        )
    }

    /// 標題列、切換鈕、倒數日離螢幕邊緣 20：外層已經有月曆的 8，這裡再補 12
    private let inset = DT.Size.screenMargin - Theme.Grid.margin
    /// 右下角新增鈕的直徑
    private let fabSize: CGFloat = 56

    var body: some View {
        VStack(spacing: DT.Space.s3) {
            header
            if coach.showsIntroCard { introCard }
            if !vm.countdowns.isEmpty { countdownStrip }
            if let message = app.store.lastError ?? app.settings.errorMessage {
                Text(message)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset)
            }
            content
                // 捲到底時多留一段，最後一列才不會被右下角的新增鈕蓋住
                .contentMargins(.bottom, fabSize + DT.Space.s4, for: .scrollContent)
                .coachTarget(CoachTargetID.content)
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .padding(.horizontal, Theme.Grid.margin)
        .padding(.top, DT.Space.s2)
        .background(Theme.bg.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear {
            vm.autoDetectHolidaysIfNeeded()
            vm.rebuild()
        }
        .onChange(of: app.store.changeToken) { vm.rebuild() }
        .onChange(of: app.settings.value) { vm.rebuild() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.rebuild() }
        }
        .sheet(item: $sheet) { kind in
            sheetView(kind)
        }
        .alert("格子裡顯示的短名", isPresented: $showShortName) {
            TextField("最多 6 個字", text: $shortNameText)
            Button("儲存") {
                if let t = shortNameTarget { app.settings.setShortName(shortNameText, for: t.seriesID) }
            }
            Button("清除短名", role: .destructive) {
                if let t = shortNameTarget { app.settings.setShortName("", for: t.seriesID) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(shortNameTarget?.title ?? "")
        }
    }

    // MARK: 標題列

    private var header: some View {
        HStack(spacing: DT.Space.s2) {
            mainMenu
            Button { sheet = .monthPicker } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(vm.titleMonthText).dFont(DT.TypeScale.largeTitle).foregroundStyle(Theme.ink)
                    Text(vm.titleYearText).dFont(DT.TypeScale.subheadline).foregroundStyle(Theme.sub)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minHeight: DT.Size.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(vm.titleYearText) 年 \(vm.titleMonthText)，點一下選擇年月")
            .coachTarget(CoachTargetID.monthTitle)
            Spacer(minLength: 0)
            PillTextButton(title: "今天") { vm.goToday() }
        }
        .padding(.horizontal, inset)
    }

    /// 右下角的新增鈕，浮在內容上面
    private var addButton: some View {
        CircleIconButton(systemName: "plus", label: "新增行程", primary: true, size: fabSize) {
            sheet = .newEvent(vm.focusDate)
        }
        .padding(.trailing, inset)
        .padding(.bottom, DT.Space.s4)
    }

    /// 標題列的選單鈕：五種檢視、搜尋、設定都收在這裡
    private var mainMenu: some View {
        Menu {
            Picker("檢視", selection: app.settings.binding(\.view)) {
                ForEach(ViewKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            Divider()
            Button("搜尋", systemImage: "magnifyingglass") { sheet = .search }
            Button("設定", systemImage: "gearshape") { sheet = .settings }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: DT.Size.iconButton, height: DT.Size.iconButton)
                .background(Circle().fill(Theme.card))
                .domyShadow(DT.Elevation.level1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("選單：切換檢視、搜尋、設定")
        .coachTarget(CoachTargetID.menu)
    }

    /// 沒看過引導的人才看得到。引導不自動開始，點這張卡才開始；按 ✕ 就不再出現。
    private var introCard: some View {
        HStack(spacing: 0) {
            Button {
                coach.requestStart()
            } label: {
                Text("第一次用？花一分鐘看怎麼用")
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.ink)
                    // 字體放大後會換行，上下留一點才不會貼到卡片邊
                    .padding(.vertical, DT.Space.s2)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
                    .padding(.leading, DT.Space.s4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            Button {
                coach.dismissIntroCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.sub)
                    .frame(width: DT.Size.touch, height: DT.Size.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("關閉，不再顯示")
        }
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
        .padding(.horizontal, inset)
    }

    private var countdownStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DT.Space.s2) {
                ForEach(vm.countdowns) { item in
                    Button { vm.show(item.date) } label: {
                        HStack(spacing: DT.Space.s2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(vm.color(item.categoryID))
                                .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                            Text(item.title).dFont(DT.TypeScale.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(item.text).dFont(DT.TypeScale.callout).foregroundStyle(Theme.strong)
                        }
                        .padding(.horizontal, DT.Space.s4)
                        .frame(minHeight: DT.Size.touch)
                        .background(Capsule().fill(Theme.card))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(item.title)，\(item.text)")
                }
            }
            .padding(.horizontal, inset)
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        switch app.settings.value.view {
        case .agenda:
            AgendaView(vm: vm, actions: actions)
        case .week, .threeDay, .day:
            DayGridView(vm: vm, actions: actions)
        case .month:
            if mode == .list {
                ListModeView(vm: vm, actions: actions)
            } else {
                VStack(spacing: DT.Space.s2) {
                    if mode != .strips { weekdayHeader }
                    weekScroll
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: Theme.Grid.gap) {
            ForEach(vm.weekdaySymbols, id: \.self) { s in
                Text(s).dFont(DT.TypeScale.caption).foregroundStyle(Theme.sub).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var weekScroll: some View {
        @Bindable var model = vm
        return ScrollView {
            LazyVStack(spacing: DT.Space.s2) {
                ForEach(vm.weeks) { week in
                    WeekBlock(vm: vm, week: week, mode: mode, actions: actions)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, DT.Space.s2)
            HStack(spacing: DT.Space.s2) {
                WideButton(title: "更早的月份", kind: .secondary) { vm.loadEarlier() }
                WideButton(title: "更晚的月份", kind: .secondary) { vm.loadLater() }
            }
            .padding(.horizontal, inset)
            .padding(.bottom, DT.Space.s8)
        }
        .scrollPosition(id: $model.topWeekID, anchor: .top)
    }

    // MARK: 彈出畫面

    @ViewBuilder
    private func sheetView(_ kind: SheetKind) -> some View {
        switch kind {
        case .newEvent(let date):
            EventEditor(store: app.store, event: nil, defaultDay: date, calendar: vm.calendar) { sheet = nil }
                .ignoresSafeArea()
        case .edit(let event):
            if let ek = app.store.ekEvent(for: event) {
                EventEditor(store: app.store, event: ek, defaultDay: event.start, calendar: vm.calendar) { sheet = nil }
                    .ignoresSafeArea()
            } else {
                MissingEventView { sheet = nil }
            }
        case .settings:
            SettingsScreen()
        case .search:
            SearchScreen()
        case .monthPicker:
            MonthPickerSheet(initial: vm.titleDate) { date in
                vm.jump(to: date, select: false)
            }
        }
    }
}

/// 一週：依呈現方式畫，被選的那天在這週時下面多一塊時間表
struct WeekBlock: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let mode: DisplayMode
    let actions: CalendarActions

    var body: some View {
        VStack(spacing: DT.Space.s2) {
            if mode == .strips {
                StripWeek(vm: vm, week: week, actions: actions)
            } else if week.isCollapsed {
                CollapsedWeek(vm: vm, week: week, actions: actions)
            } else {
                ExpandedWeek(vm: vm, week: week, showAll: mode == .flex, actions: actions)
            }
            if let sel = vm.selected, let day = week.days.first(where: { $0.date == sel }) {
                DayPanel(vm: vm, day: day, actions: actions)
            }
        }
    }
}

struct MissingEventView: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: DT.Space.s4) {
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "找不到這個行程",
                message: "它可能剛被刪除，或是移到別的行事曆了。"
            )
            WideButton(title: "關閉", kind: .secondary, action: close)
        }
        .padding(DT.Size.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    let onPick: (Date) -> Void

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        _date = State(initialValue: initial)
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            DatePicker("日期", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .navigationTitle("跳到指定日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("前往") {
                            onPick(date)
                            dismiss()
                        }
                    }
                }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium])
    }
}
