import SwiftUI
import EventKit
import CalendarCore

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var settings: SettingsStore { app.settings }

    var body: some View {
        NavigationStack {
            Form {
                if let message = settings.errorMessage {
                    Section {
                        Text(message).foregroundStyle(Theme.holiday)
                    }
                }
                displaySection
                calendarSection
                categorySection
                countdownSection
                aboutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: 顯示

    private var displaySection: some View {
        Section("顯示") {
            Picker("一週從哪天開始", selection: settings.binding(\.weekStartsOnMonday)) {
                Text("週日").tag(false)
                Text("週一").tag(true)
            }
            Toggle("顯示農曆與節氣", isOn: settings.binding(\.showLunar))
        }
    }

    // MARK: 行事曆

    private var calendarSection: some View {
        Section {
            ForEach(app.store.calendars, id: \.calendarIdentifier) { cal in
                CalendarRoleRow(settings: settings, calendar: cal)
            }
        } header: {
            Text("行事曆")
        } footer: {
            Text("每一本行事曆可以歸到一個類別、當成節日層，或是不顯示。這裡只改蒜日子的顯示方式，不會動到系統行事曆。")
        }
    }

    // MARK: 類別

    private var categorySection: some View {
        Section {
            ForEach(settings.value.categories) { cat in
                CategoryRow(settings: settings, categoryID: cat.id)
            }
            .onDelete { offsets in
                let ids = offsets.map { settings.value.categories[$0].id }
                for id in ids { settings.removeCategory(id) }
            }
            Button("新增類別") {
                settings.update {
                    $0.categories.append(EventCategory(id: UUID().uuidString, name: "新類別", colorHex: "#475569"))
                }
            }
        } header: {
            Text("類別")
        } footer: {
            Text("開啟「優先」的類別，在同一天有多件事時會優先當主事件。往左滑可以刪除類別，至少要留一個。")
        }
    }

    // MARK: 倒數日

    @ViewBuilder
    private var countdownSection: some View {
        if !settings.value.countdowns.isEmpty {
            Section {
                ForEach(settings.value.countdowns, id: \.self) { id in
                    Text(app.store.title(forSeries: id) ?? "（找不到這個行程）")
                }
                .onDelete { offsets in
                    settings.update { $0.countdowns.remove(atOffsets: offsets) }
                }
            } header: {
                Text("倒數日")
            } footer: {
                Text("在某一天的時間表裡長按行程，可以加入倒數日。")
            }
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            Text("蒜日子直接讀寫 iPhone 的系統行事曆，沒有自己的帳號，也不會把行程傳到任何伺服器。置頂、短名、類別這些設定只存在這支手機。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// 一本行事曆的角色：某個類別、節日層、不顯示
struct CalendarRoleRow: View {
    let settings: SettingsStore
    let calendar: EKCalendar

    private static let holidayTag = "__holiday__"
    private static let hiddenTag = "__hidden__"
    private static let noneTag = "__none__"

    private var role: Binding<String> {
        let id = calendar.calendarIdentifier
        return Binding(
            get: {
                let s = settings.value
                if s.hiddenCalendarIDs.contains(id) { return Self.hiddenTag }
                if s.holidayCalendarIDs.contains(id) { return Self.holidayTag }
                if let cat = s.calendarCategory[id], s.categories.contains(where: { $0.id == cat }) { return cat }
                return Self.noneTag
            },
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
        Picker(selection: role) {
            Text("未分類（當成行程）").tag(Self.noneTag)
            ForEach(settings.value.categories) { cat in
                Text(cat.name).tag(cat.id)
            }
            Text("節日層").tag(Self.holidayTag)
            Text("不顯示").tag(Self.hiddenTag)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                Text(calendar.title)
            }
        }
    }
}

struct CategoryRow: View {
    let settings: SettingsStore
    let categoryID: String

    private var index: Int? {
        settings.value.categories.firstIndex { $0.id == categoryID }
    }

    private var name: Binding<String> {
        Binding(
            get: { index.map { settings.value.categories[$0].name } ?? "" },
            set: { v in
                settings.update { s in
                    if let i = s.categories.firstIndex(where: { $0.id == categoryID }) { s.categories[i].name = v }
                }
            }
        )
    }

    private var color: Binding<Color> {
        Binding(
            get: { index.flatMap { Color(hex: settings.value.categories[$0].colorHex) } ?? Theme.fallbackCategory },
            set: { v in
                settings.update { s in
                    if let i = s.categories.firstIndex(where: { $0.id == categoryID }) { s.categories[i].colorHex = v.hexString }
                }
            }
        )
    }

    private var priority: Binding<Bool> {
        Binding(
            get: { index.map { settings.value.categories[$0].isPriority } ?? false },
            set: { v in
                settings.update { s in
                    if let i = s.categories.firstIndex(where: { $0.id == categoryID }) { s.categories[i].isPriority = v }
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("顏色", selection: color, supportsOpacity: false)
                .labelsHidden()
            TextField("類別名稱", text: name)
            Toggle("優先", isOn: priority)
                .fixedSize()
        }
    }
}
