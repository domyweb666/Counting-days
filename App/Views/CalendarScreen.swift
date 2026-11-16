import SwiftUI
import EventKit
import CalendarCore

enum SheetKind: Identifiable {
    case newEvent(Date)
    case edit(CalEvent)
    case settings
    case search
    case monthPicker
    case fullVersion(FullVersionReason)

    var id: String {
        switch self {
        case .newEvent(let d): return "new\(d.timeIntervalSinceReferenceDate)"
        case .edit(let e): return "edit" + e.id
        case .settings: return "settings"
        case .search: return "search"
        case .monthPicker: return "month"
        case .fullVersion(let reason): return "full" + reason.rawValue
        }
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: SheetKind?
    /// 側邊欄有沒有打開
    @State private var showSideMenu = false
    /// 正在編輯的那個行程，打開時找一次就記住。
    /// 刪掉行程的那一刻系統行事曆會通知有變動、畫面重畫；那時候再去找，剛刪掉的行程找不到，
    /// 編輯畫面會被換成「找不到這個行程」，系統也來不及通知我們關掉。
    @State private var editing: EKEvent?
    /// 那個行程能用蒜日子自己的畫面改時，表單要帶入的東西；nil 就開系統的編輯畫面。一樣是打開時算一次就記住。
    @State private var editSeed: EventStore.EditSeed?
    @State private var shortNameTarget: CalEvent?
    @State private var shortNameText = ""
    @State private var showShortName = false

    private var vm: CalendarViewModel { app.vm }
    /// 月曆樣式（在設定裡選）
    private var mode: DisplayMode { app.settings.effectiveMode }

    private var actions: CalendarActions {
        CalendarActions(
            open: { event in
                editing = app.store.ekEvent(for: event)
                editSeed = app.store.editSeed(
                    for: event,
                    ownCategoryID: app.settings.value.eventCategory[event.seriesID],
                    calendar: vm.calendar
                )
                sheet = .edit(event)
            },
            add: { sheet = .newEvent($0) },
            shortName: { event in
                shortNameTarget = event
                shortNameText = app.settings.value.shortNames[event.seriesID] ?? ""
                showShortName = true
            },
            needFullVersion: { sheet = .fullVersion($0) }
        )
    }

    /// 標題列、切換鈕、倒數日離螢幕邊緣 20：外層已經有月曆的 8，這裡再補 12
    private let inset = DT.Size.screenMargin - Theme.Grid.margin
    /// 右下角新增鈕的直徑
    private let fabSize: CGFloat = 56
    /// 剛進月曆時，等多久再指定一次捲動位置；清掉與放回之間隔多久
    private let settleDelay: Double = 0.15
    private let settleGap: Double = 0.05
    /// 側邊欄的寬度、logo 的邊長、滑出來花多久、往左滑多遠算要收起來
    private let sideMenuWidth: CGFloat = 288
    private let sideMenuLogo: CGFloat = 40
    private let sideMenuDuration: Double = 0.25
    private let sideMenuSwipe: CGFloat = 40

    var body: some View {
        VStack(spacing: DT.Space.s3) {
            header
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
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .padding(.horizontal, Theme.Grid.margin)
        .padding(.top, DT.Space.s2)
        .background(Theme.bg.ignoresSafeArea())
        // 側邊欄打開時，後面的月曆不讓 VoiceOver 唸
        .accessibilityHidden(showSideMenu)
        .overlay { sideMenu }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear {
            vm.autoDetectHolidaysIfNeeded()
            vm.rebuild()
        }
        .task { await settleFirstScroll() }
        .onChange(of: app.store.changeToken) { vm.rebuild() }
        .onChange(of: app.settings.value) { vm.rebuild() }
        // 驗到購買（或退款）之後，顯示幾個倒數日會變
        .onChange(of: app.purchase.isUnlocked) { vm.rebuild() }
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

    /// 剛進月曆時，行程還沒載進來就先指定了捲動位置，上面那些收成一行的週高度還沒確定，
    /// 結果會差半列，今天那一週的日期被星期列蓋住。等排好之後再指定一次。
    /// 位置要「有變」才會捲，所以先清掉再放回去。
    private func settleFirstScroll() async {
        let week = vm.topWeekID
        do {
            try await Task.sleep(for: .seconds(settleDelay))
            // 這段時間使用者自己捲了，就不要把他拉回去
            guard vm.topWeekID == week else { return }
            vm.topWeekID = nil
            try await Task.sleep(for: .seconds(settleGap))
            guard vm.topWeekID == nil else { return }
            vm.topWeekID = week
        } catch {
            // 只有畫面離開、工作被取消才會到這裡，不用再捲
            return
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
            // 跑到別的月份時才出現。右邊的「今天」做的是同一件事，這顆放在標題旁邊比較順手。
            if !vm.isShowingThisMonth {
                CircleIconButton(systemName: "arrow.uturn.backward", label: "回到今天") { vm.goToday() }
            }
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

    /// 標題列的選單鈕：按了從左邊滑出側邊欄
    private var mainMenu: some View {
        CircleIconButton(systemName: "line.3.horizontal", label: "選單：切換檢視、搜尋、設定") {
            showSideMenu = true
        }
    }

    // MARK: 側邊欄

    /// 蓋在整個畫面上：後面一層暗幕，左邊一條側邊欄。點暗幕或把側邊欄往左滑就收起來。
    /// iPhone 內建的選單放不了 logo，圖示也只能在右邊，所以自己畫。
    private var sideMenu: some View {
        ZStack(alignment: .leading) {
            if showSideMenu {
                Theme.scrim
                    .ignoresSafeArea()
                    .onTapGesture { showSideMenu = false }
                    .accessibilityLabel("關閉選單")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                sideMenuPanel
                    // 開了「減少動態效果」就不滑，只淡入淡出
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    // 收起來的途中也要壓在暗幕上面
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: sideMenuDuration), value: showSideMenu)
    }

    private var sideMenuPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s1) {
                HStack(spacing: DT.Space.s3) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: sideMenuLogo, height: sideMenuLogo)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
                        .accessibilityHidden(true)
                    Text("蒜日子")
                        .dFont(DT.TypeScale.title2)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, DT.Space.s4)
                .padding(.top, DT.Space.s4)
                .padding(.bottom, DT.Space.s4)
                ForEach(ViewKind.allCases, id: \.self) { kind in
                    sideMenuRow(
                        title: kind.label,
                        isCurrent: kind == app.settings.value.view,
                        icon: { viewKindIcon(kind) },
                        action: {
                            app.settings.update { $0.view = kind }
                            showSideMenu = false
                        }
                    )
                }
                Hairline()
                    .padding(.horizontal, DT.Space.s4)
                    .padding(.vertical, DT.Space.s2)
                sideMenuRow(
                    title: "搜尋",
                    isCurrent: false,
                    icon: { symbolIcon("magnifyingglass") },
                    action: {
                        showSideMenu = false
                        sheet = .search
                    }
                )
                sideMenuRow(
                    title: "設定",
                    isCurrent: false,
                    icon: { symbolIcon("gearshape") },
                    action: {
                        showSideMenu = false
                        sheet = .settings
                    }
                )
            }
            .padding(.trailing, DT.Space.s3)
            .padding(.bottom, DT.Space.s6)
        }
        .frame(width: sideMenuWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.card.ignoresSafeArea())
        // 上下捲不算，往左滑夠遠才收
        .simultaneousGesture(
            DragGesture(minimumDistance: sideMenuSwipe).onEnded { drag in
                let across = drag.translation.width
                if across < -sideMenuSwipe, abs(drag.translation.height) < abs(across) {
                    showSideMenu = false
                }
            }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { showSideMenu = false }
    }

    /// 側邊欄的一列：圖示在左、名稱在右。目前那種檢視整列標起來，左邊貼齊螢幕邊緣、右邊是圓的。
    private func sideMenuRow<Icon: View>(
        title: String,
        isCurrent: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s4) {
                icon()
                    .frame(width: DT.Space.s8)
                Text(title).dFont(DT.TypeScale.headline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isCurrent ? Theme.strong : Theme.ink)
            .padding(.horizontal, DT.Space.s4)
            .frame(minHeight: DT.Size.row)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: DT.Size.row / 2, topTrailingRadius: DT.Size.row / 2
                )
                .fill(isCurrent ? Theme.soft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func symbolIcon(_ systemName: String) -> some View {
        Image(systemName: systemName).font(.system(size: 17, weight: .semibold))
    }

    /// 五種檢視的小圖示：一個框裡分成幾欄幾列，就是那種檢視一次排的樣子。
    /// 月是格子、時間表是上下兩列、週是四欄、3 天是三欄、天是一整格。
    private func viewKindIcon(_ kind: ViewKind) -> some View {
        let columns: Int
        let rows: Int
        switch kind {
        case .month:
            columns = 3
            rows = 2
        case .agenda:
            columns = 1
            rows = 2
        case .week:
            columns = 4
            rows = 1
        case .threeDay:
            columns = 3
            rows = 1
        case .day:
            columns = 1
            rows = 1
        }
        let line: CGFloat = 2
        return RoundedRectangle(cornerRadius: DT.Radius.sm / 2)
            .strokeBorder(lineWidth: line)
            .overlay {
                GeometryReader { geo in
                    Path { path in
                        for column in 1..<columns {
                            let x = geo.size.width * CGFloat(column) / CGFloat(columns)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        for row in 1..<rows {
                            let y = geo.size.height * CGFloat(row) / CGFloat(rows)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                    }
                    .stroke(lineWidth: line)
                }
            }
            .frame(width: 24, height: 18)
            .accessibilityHidden(true)
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
            NewEventScreen(day: date, calendar: vm.calendar) { sheet = nil }
        case .edit(let event):
            if let editSeed {
                NewEventScreen(seed: editSeed, calendar: vm.calendar) { sheet = nil }
            } else if let editing {
                EventEditor(store: app.store, event: editing, defaultDay: event.start, calendar: vm.calendar) { sheet = nil }
                    .ignoresSafeArea()
            } else {
                MissingEventView { sheet = nil }
            }
        case .settings:
            SettingsScreen()
        case .search:
            SearchScreen()
        case .monthPicker:
            MonthPickerSheet(initial: vm.titleDate, timeZone: vm.calendar.timeZone) { date in
                vm.jump(to: date, select: false)
            }
        case .fullVersion(let reason):
            FullVersionSheet(reason: reason)
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
    /// 月曆照哪個時區排，滾輪就照哪個時區，選到的才是同一天
    let timeZone: TimeZone
    let onPick: (Date) -> Void

    init(initial: Date, timeZone: TimeZone, onPick: @escaping (Date) -> Void) {
        _date = State(initialValue: initial)
        self.timeZone = timeZone
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            DatePicker("日期", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .environment(\.timeZone, timeZone)
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
