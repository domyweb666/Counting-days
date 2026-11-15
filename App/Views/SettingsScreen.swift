import SwiftUI
import EventKit
import CalendarCore

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(CoachController.self) private var coach
    @Environment(\.dismiss) private var dismiss

    private var settings: SettingsStore { app.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("設定")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message = settings.errorMessage {
                    Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
                }
                displaySection
                weatherSection
                calendarSection
                categorySection
                countdownSection
                aboutSection
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
    }

    // MARK: 顯示

    private var displaySection: some View {
        SectionCard(title: "顯示") {
            SettingsRow(label: "月曆樣式") {
                Menu {
                    Picker("月曆樣式", selection: settings.binding(\.mode)) {
                        ForEach(DisplayMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                } label: {
                    PickerCapsule(text: settings.value.mode.label)
                }
                .buttonStyle(.plain)
            }
            Hairline()
            SettingsRow(label: "一週從哪天開始") {
                Menu {
                    Picker("一週從哪天開始", selection: settings.binding(\.weekStartsOnMonday)) {
                        Text("週日").tag(false)
                        Text("週一").tag(true)
                    }
                } label: {
                    PickerCapsule(text: settings.value.weekStartsOnMonday ? "週一" : "週日")
                }
                .buttonStyle(.plain)
            }
            Hairline()
            SettingsRow(label: "顯示農曆與節氣") {
                Toggle("顯示農曆與節氣", isOn: settings.binding(\.showLunar))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
        }
    }

    // MARK: 天氣

    private var weatherSection: some View {
        let enabled = settings.value.weatherEnabled
        let city = WeatherCity.find(settings.value.weatherCityID)
        return SectionCard(
            title: "天氣",
            footer: enabled && city == nil
                ? "選一個縣市才會顯示天氣。"
                : "天氣還在製作中。這一版只會記住你選的縣市，不會連網。"
        ) {
            SettingsRow(label: "顯示天氣") {
                Toggle("顯示天氣", isOn: settings.binding(\.weatherEnabled))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            if enabled {
                Hairline()
                SettingsRow(label: "縣市") {
                    Menu {
                        ForEach(WeatherCity.all) { item in
                            Button {
                                settings.update { $0.weatherCityID = item.id }
                            } label: {
                                if item.id == city?.id {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    } label: {
                        PickerCapsule(text: city?.name ?? "選擇縣市")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("縣市：\(city?.name ?? "還沒選")")
                }
            }
        }
    }

    // MARK: 行事曆

    private var calendarSection: some View {
        let calendars = app.store.calendars
        return SectionCard(
            title: "行事曆",
            footer: "每一本行事曆可以歸到一個類別、當成節日層，或是不顯示。這裡只改蒜日子的顯示方式，不會動到系統行事曆。"
        ) {
            if calendars.isEmpty {
                SettingsRow(label: "這支手機還沒有任何行事曆") { EmptyView() }
            }
            ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, cal in
                if index > 0 { Hairline() }
                CalendarRoleRow(settings: settings, calendar: cal)
            }
        }
    }

    // MARK: 類別

    private var categorySection: some View {
        let categories = settings.value.categories
        return SectionCard(
            title: "類別",
            footer: "開啟「優先」的類別，在同一天有多件事時會優先當主事件。類別至少要留一個。"
        ) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                if index > 0 { Hairline() }
                CategoryRow(settings: settings, categoryID: cat.id, canDelete: categories.count > 1)
            }
            Hairline()
            Button {
                settings.update {
                    $0.categories.append(EventCategory(id: UUID().uuidString, name: "新類別", colorHex: "#66666D"))
                }
            } label: {
                Text("新增類別")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.strong)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: 倒數日

    @ViewBuilder
    private var countdownSection: some View {
        let ids = settings.value.countdowns
        if !ids.isEmpty {
            SectionCard(title: "倒數日", footer: "在某一天的時間表裡長按行程，可以加入倒數日。") {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if index > 0 { Hairline() }
                    SettingsRow(label: app.store.title(forSeries: id) ?? "（找不到這個行程）") {
                        Button {
                            settings.toggleCountdown(id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.sub)
                                .frame(width: DT.Size.touch, height: DT.Size.touch)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("移出倒數日")
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        SectionCard(
            title: "關於",
            footer: "蒜日子直接讀寫 iPhone 的系統行事曆，沒有自己的帳號，也不會把行程傳到任何伺服器。置頂、短名、類別這些設定只存在這支手機。"
        ) {
            SettingsRow(label: "版本") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.sub)
            }
            Hairline()
            Button {
                // 引導的遮罩蓋不到彈出視窗，先關掉設定再開始
                coach.requestStart()
                dismiss()
            } label: {
                Text("重看教學")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.strong)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// 設定列：左邊標題，右邊放開關、選單或文字。列本身保持中性。
struct SettingsRow<Trailing: View>: View {
    let label: String
    var dotColor: Color?
    let trailing: Trailing

    init(label: String, dotColor: Color? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.dotColor = dotColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DT.Space.s3) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: Theme.Grid.square, height: Theme.Grid.square)
            }
            Text(label)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, DT.Space.s2)
        .frame(minHeight: DT.Size.row)
    }
}

/// 一本行事曆的角色：某個類別、節日層、不顯示
struct CalendarRoleRow: View {
    let settings: SettingsStore
    let calendar: EKCalendar

    private static let holidayTag = "__holiday__"
    private static let hiddenTag = "__hidden__"
    private static let noneTag = "__none__"

    private var currentTag: String {
        let id = calendar.calendarIdentifier
        let s = settings.value
        if s.hiddenCalendarIDs.contains(id) { return Self.hiddenTag }
        if s.holidayCalendarIDs.contains(id) { return Self.holidayTag }
        if let cat = s.calendarCategory[id], s.categories.contains(where: { $0.id == cat }) { return cat }
        return Self.noneTag
    }

    private var currentText: String {
        switch currentTag {
        case Self.hiddenTag: return "不顯示"
        case Self.holidayTag: return "節日層"
        case Self.noneTag: return "未分類"
        default: return settings.value.category(id: currentTag).name
        }
    }

    private var role: Binding<String> {
        let id = calendar.calendarIdentifier
        return Binding(
            get: { currentTag },
            set: { tag in
                settings.update { s in
                    s.hiddenCalendarIDs.remove(id)
                    s.holidayCalendarIDs.remove(id)
                    s.calendarCategory.removeValue(forKey: id)
                    switch tag {
                    case Self.hiddenTag: s.hiddenCalendarIDs.insert(id)
                    case Self.holidayTag: s.holidayCalendarIDs.insert(id)
                    case Self.noneTag: break
                    default: s.calendarCategory[id] = tag
                    }
                }
            }
        )
    }

    var body: some View {
        SettingsRow(label: calendar.title, dotColor: Color(cgColor: calendar.cgColor)) {
            Menu {
                Picker(calendar.title, selection: role) {
                    Text("未分類（當成行程）").tag(Self.noneTag)
                    ForEach(settings.value.categories) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                    Text("節日層").tag(Self.holidayTag)
                    Text("不顯示").tag(Self.hiddenTag)
                }
            } label: {
                PickerCapsule(text: currentText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(calendar.title)：\(currentText)")
        }
    }
}

struct CategoryRow: View {
    let settings: SettingsStore
    let categoryID: String
    let canDelete: Bool

    private var index: Int? {
        settings.value.categories.firstIndex { $0.id == categoryID }
    }

    private func change(_ edit: @escaping (inout EventCategory) -> Void) {
        settings.update { s in
            if let i = s.categories.firstIndex(where: { $0.id == categoryID }) { edit(&s.categories[i]) }
        }
    }

    private var name: Binding<String> {
        Binding(
            get: { index.map { settings.value.categories[$0].name } ?? "" },
            set: { v in change { $0.name = v } }
        )
    }

    private var color: Binding<Color> {
        Binding(
            get: { index.map { Theme.category(hex: settings.value.categories[$0].colorHex).fill } ?? Theme.sub },
            set: { v in change { $0.colorHex = v.hexString } }
        )
    }

    private var priority: Binding<Bool> {
        Binding(
            get: { index.map { settings.value.categories[$0].isPriority } ?? false },
            set: { v in change { $0.isPriority = v } }
        )
    }

    var body: some View {
        HStack(spacing: DT.Space.s3) {
            ColorPicker("顏色", selection: color, supportsOpacity: false)
                .labelsHidden()
            TextField("類別名稱", text: name)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.ink)
            Text("優先").dFont(DT.TypeScale.footnote).foregroundStyle(Theme.sub)
            Toggle("優先", isOn: priority)
                .labelsHidden()
                .tint(Theme.accent)
            if canDelete {
                Menu {
                    Button("刪除這個類別", systemImage: "trash", role: .destructive) {
                        settings.removeCategory(categoryID)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                        .frame(width: DT.Space.s8, height: DT.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多")
            }
        }
        .padding(.vertical, DT.Space.s1)
        .frame(minHeight: DT.Size.row)
    }
}
