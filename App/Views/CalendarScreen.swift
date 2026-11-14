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
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: SheetKind?
    @State private var shortNameTarget: CalEvent?
    @State private var shortNameText = ""
    @State private var showShortName = false

    private var vm: CalendarViewModel { app.vm }
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

    var body: some View {
        VStack(spacing: 10) {
            header
            modeTabs
            if !vm.countdowns.isEmpty { countdownStrip }
            if let message = app.store.lastError ?? app.settings.errorMessage {
                Text(message)
                    .sFont(13, .bold)
                    .foregroundStyle(Theme.holiday)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            content
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
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
        HStack(spacing: 8) {
            Button { sheet = .monthPicker } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(vm.titleMonthText).sFont(34, .black).foregroundStyle(Theme.ink)
                    Text(vm.titleYearText).sFont(15, .medium).foregroundStyle(Theme.sub)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.sub)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(vm.titleYearText) 年 \(vm.titleMonthText)，點一下選擇年月")
            Spacer(minLength: 0)
            iconButton("magnifyingglass", label: "搜尋") { sheet = .search }
            iconButton("gearshape", label: "設定") { sheet = .settings }
            Button { vm.goToday() } label: {
                Text("今天")
                    .sFont(15, .bold)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Capsule().fill(Theme.card))
            }
            .buttonStyle(.plain)
            Button { sheet = .newEvent(vm.selected ?? vm.today) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.inkInverse)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增行程")
        }
        .padding(.horizontal, 4)
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var modeTabs: some View {
        HStack(spacing: 2) {
            ForEach(DisplayMode.allCases, id: \.self) { m in
                let on = m == mode
                Button {
                    app.settings.update { $0.mode = m }
                } label: {
                    Text(m.label)
                        .sFont(14, .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Theme.inkInverse : Theme.pastFg)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(on ? Theme.ink : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.card))
        .padding(.horizontal, 4)
    }

    private var countdownStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.countdowns) { item in
                    Button { vm.jump(to: item.date) } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(vm.color(item.categoryID))
                                .frame(width: 10, height: 10)
                            Text(item.title).sFont(14, .bold).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(item.text).sFont(14, .heavy).foregroundStyle(vm.color(item.categoryID))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title)，\(item.text)")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        if mode == .list {
            ListModeView(vm: vm, actions: actions)
        } else {
            VStack(spacing: 6) {
                if mode != .strips { weekdayHeader }
                weekScroll
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 3) {
            ForEach(vm.weekdaySymbols, id: \.self) { s in
                Text(s).sFont(12, .medium).foregroundStyle(Theme.sub).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var weekScroll: some View {
        @Bindable var model = vm
        return ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vm.weeks) { week in
                    WeekBlock(vm: vm, week: week, mode: mode, actions: actions)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 8)
            HStack(spacing: 8) {
                loadButton("載入更早的月份") { vm.loadEarlier() }
                loadButton("載入更晚的月份") { vm.loadLater() }
            }
            .padding(.bottom, 16)
        }
        .scrollPosition(id: $model.topWeekID, anchor: .top)
    }

    private func loadButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .sFont(13, .bold)
                .foregroundStyle(Theme.pastFg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 6) {
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
        VStack(spacing: 16) {
            Text("找不到這個行程").sFont(19, .heavy)
            Text("它可能剛被刪除或移到別的行事曆。").sFont(15).foregroundStyle(Theme.sub)
            Button("關閉", action: close).buttonStyle(.borderedProminent)
        }
        .padding(24)
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
        .presentationDetents([.medium])
    }
}
