import SwiftUI
import EventKit
import CalendarCore

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showCategories = false
    @State private var showThemes = false
    @State private var showModes = false

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
                // 天氣還沒做完，開了也不會有東西，先不放 weatherSection。做完第 8 片再放回來。
                calendarSection
                categoryLink
                countdownSection
                aboutSection
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .sheet(isPresented: $showCategories) {
            CategorySettingsScreen()
        }
    }

    // MARK: 顯示

    private var displaySection: some View {
        SectionCard(title: "顯示") {
            Button {
                showThemes = true
            } label: {
                HStack(spacing: DT.Space.s3) {
                    Text("主題")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Theme.current.name)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.sub)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                }
                .frame(minHeight: DT.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .sheet(isPresented: $showThemes) {
                ThemeSettingsScreen()
            }
            Hairline()
            // 有兩種樣式要完整版，可以先試看，所以跟主題一樣收在第二頁
            Button {
                showModes = true
            } label: {
                HStack(spacing: DT.Space.s3) {
                    Text("月曆樣式")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(settings.effectiveMode.label)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.sub)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                }
                .frame(minHeight: DT.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .sheet(isPresented: $showModes) {
                DisplayModeSettingsScreen()
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
            footer: "每一本行事曆歸一個類別，月曆上就用那個類別的顏色。也可以當成節日，或是不顯示。這裡只改蒜日子的顯示方式，不會動到系統行事曆。"
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

    // MARK: 類別（收在第二頁）

    private var categoryLink: some View {
        SectionCard(footer: "改類別的名稱、顏色，或指定哪一類優先當主事件。") {
            Button {
                showCategories = true
            } label: {
                HStack(spacing: DT.Space.s3) {
                    Text("類別與顏色")
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                }
                .frame(minHeight: DT.Size.row)
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
            SectionCard(title: "倒數日", footer: countdownFooter) {
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

    private var countdownFooter: String {
        let base = "在某一天的時間表裡長按行程，可以加入倒數日。"
        // 退款之後超過上限的不刪，只是月曆上先不顯示
        guard settings.visibleCountdowns.count < settings.value.countdowns.count else { return base }
        return base + "免費版在月曆上只顯示最上面 \(FullVersionAccess.freeCountdownLimit) 個，其餘留在這裡，解鎖完整版後會回來。"
    }

    private var aboutSection: some View {
        SectionCard(
            title: "關於",
            footer: "蒜日子直接讀寫 iPhone 的系統行事曆，沒有自己的帳號，也不會把行程傳到任何伺服器。置頂、短名、類別這些設定只存在這支手機。購買完整版由 Apple 處理，蒜日子拿不到你的付款資料。"
        ) {
            SettingsRow(label: "版本") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.sub)
            }
        }
    }
}

/// 設定的第二頁：類別的名稱、顏色、優先
struct CategorySettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showFullVersion = false

    private var settings: SettingsStore { app.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("類別與顏色")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message = settings.errorMessage {
                    Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
                }
                categorySection
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .sheet(isPresented: $showFullVersion) {
            FullVersionSheet(reason: .categoryColor)
        }
    }

    private var categorySection: some View {
        let categories = settings.value.categories
        return SectionCard(
            title: nil,
            footer: "點左邊的圓圈改顏色，點名稱可以改字。前四個顏色會跟著主題換。開啟「優先」的類別，在同一天有多件事時會優先當主事件。類別至少要留一個。"
        ) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                if index > 0 { Hairline() }
                CategoryRow(
                    settings: settings,
                    categoryID: cat.id,
                    canDelete: categories.count > 1,
                    // 驗到購買之後這一列要重畫，所以多讀一次畫面看得到變化的那個值
                    canUseCustomColor: app.purchase.isUnlocked && settings.canUseCustomCategoryColor,
                    needFullVersion: { showFullVersion = true }
                )
            }
            Hairline()
            Button {
                settings.update {
                    // 新類別先用第一個預設色，會跟著主題換
                    let hex = FullVersionAccess.presetCategoryHexes.first ?? AppSettings.defaultCategories[0].colorHex
                    $0.categories.append(EventCategory(id: UUID().uuidString, name: "新類別", colorHex: hex))
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
}

/// 設定的第二頁：選主題。點一款就換，整個 app 立刻跟著變。
struct ThemeSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var settings: SettingsStore { app.settings }
    private var purchase: PurchaseStore { app.purchase }

    private var footer: String {
        let base = "深色、淺色跟著 iPhone 的外觀設定。你自己改過顏色的類別不會跟著主題換。"
        if purchase.isUnlocked { return base }
        return "上鎖的主題可以點一下試看，離開這一頁就會換回原本那款。" + base
    }

    /// 預覽用的那一週，進這一頁時算一次
    @State private var previewWeek: WeekModel?

    var body: some View {
        VStack(spacing: 0) {
            // 這一段不跟著捲：點列表最下面那幾款時，也要看得到預覽換色
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("主題")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let previewWeek { preview(previewWeek) }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s3)
            themeList
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear { previewWeek = app.vm.themePreviewWeek() }
        .task { await purchase.loadProduct() }
        // 試看只在這一頁有效，離開就換回去
        .onDisappear { settings.endThemePreview() }
    }

    /// 一週的月曆，套著現在這款主題（試看中就是試看那款）。只是樣子，點不到。
    private func preview(_ week: WeekModel) -> some View {
        VStack(alignment: .trailing, spacing: DT.Space.s1) {
            HStack(spacing: Theme.Grid.gap) {
                ForEach(week.days) { day in
                    Text(app.vm.dow(day.date))
                        .dFont(DT.TypeScale.caption)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity)
                }
            }
            ExpandedWeek(
                vm: app.vm,
                week: week,
                showAll: true,
                actions: CalendarActions(open: { _ in }, add: { _ in }, shortName: { _ in }, needFullVersion: { _ in })
            )
            Text("範例行程")
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(Theme.sub)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("主題預覽：用範例行程畫的一週月曆，會跟著你點的主題換色")
    }

    private var themeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                if let message = settings.errorMessage {
                    Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
                }
                SectionCard(footer: footer) {
                    ForEach(Array(ThemePalette.all.enumerated()), id: \.element.id) { index, palette in
                        if index > 0 { Hairline() }
                        ThemeRow(
                            palette: palette,
                            isSelected: palette.id == Theme.current.id,
                            isLocked: !ThemeAccess.canApply(palette.id, isUnlocked: purchase.isUnlocked)
                        ) {
                            pick(palette.id)
                        }
                    }
                }
                FullVersionOffer(buy: buy)
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s2)
            .padding(.bottom, DT.Space.s8)
        }
    }

    /// 買了或免費的直接套用；沒買的付費款只試看
    private func pick(_ id: String) {
        if !settings.selectTheme(id) {
            settings.previewTheme(id)
        }
    }

    private func buy() {
        // 付款視窗跳出來時這一頁可能先收到離開通知，所以先記下正在試看哪一款
        let wanted = settings.previewThemeID
        Task {
            guard await purchase.purchase() else { return }
            if let wanted { settings.selectTheme(wanted) }
        }
    }
}

/// 設定的第二頁：選月曆樣式。上面一塊範例月曆照選的樣式畫；付費的兩種可以先試看，離開這一頁就換回去。
struct DisplayModeSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// 預覽用的那一週，進這一頁時算一次
    @State private var previewWeek: WeekModel?

    private var settings: SettingsStore { app.settings }
    private var purchase: PurchaseStore { app.purchase }
    private var current: DisplayMode { settings.effectiveMode }

    private var footer: String {
        if purchase.isUnlocked { return "四種樣式都可以用，點一種上面的預覽就會換。" }
        return "上鎖的樣式可以點一下試看，離開這一頁就會換回原本那種。"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 這一段不跟著捲，點哪一種都看得到預覽
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("月曆樣式")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let previewWeek { preview(previewWeek) }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s3)
            ScrollView {
                VStack(alignment: .leading, spacing: DT.Space.s6) {
                    SectionCard(footer: footer) {
                        ForEach(Array(DisplayMode.allCases.enumerated()), id: \.element) { index, mode in
                            if index > 0 { Hairline() }
                            row(mode)
                        }
                    }
                    FullVersionOffer {
                        // 付款視窗跳出來時這一頁可能先收到離開通知，所以先記下正在試看哪一種
                        let wanted = settings.previewingMode
                        Task {
                            guard await purchase.purchase() else { return }
                            if let wanted { settings.selectMode(wanted) }
                        }
                    }
                }
                .padding(.horizontal, DT.Size.screenMargin)
                .padding(.top, DT.Space.s2)
                .padding(.bottom, DT.Space.s8)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear { previewWeek = app.vm.themePreviewWeek() }
        .task { await purchase.loadProduct() }
        // 試看只在這一頁有效，離開就換回去
        .onDisappear { settings.endModePreview() }
    }

    /// 每種樣式一句說明
    private func caption(for mode: DisplayMode) -> String {
        switch mode {
        case .flex: return "每件事都寫出來，那一週跟著長高。"
        case .list: return "小月曆用顏色標出哪天有事，下面列出接下來的行程。"
        case .strips: return "沒事的日子縮窄，有事的撐開。"
        case .head: return "每天只寫最重要的一件，其他用小色塊。"
        }
    }

    /// 買了或免費的直接套用；沒買的付費樣式只試看
    private func pick(_ mode: DisplayMode) {
        if !settings.selectMode(mode) {
            settings.previewMode(mode)
        }
    }

    private func row(_ mode: DisplayMode) -> some View {
        let isSelected = mode == current
        let isLocked = !FullVersionAccess.canApply(mode, isUnlocked: purchase.isUnlocked)
        return Button {
            pick(mode)
        } label: {
            HStack(spacing: DT.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                    Text(caption(for: mode))
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isLocked && isSelected {
                    Text("試看中")
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.strong)
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                        .frame(width: 20)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .padding(.vertical, DT.Space.s2)
            .frame(minHeight: DT.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(mode.label)，\(caption(for: mode))\(isLocked ? "，未解鎖" : "")\(isLocked && isSelected ? "，試看中" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 一週的範例月曆，照現在選的（或試看中的）樣式畫。只是樣子，點不到。
    private func preview(_ week: WeekModel) -> some View {
        let noActions = CalendarActions(open: { _ in }, add: { _ in }, shortName: { _ in }, needFullVersion: { _ in })
        return VStack(alignment: .trailing, spacing: DT.Space.s1) {
            switch current {
            case .flex:
                ExpandedWeek(vm: app.vm, week: week, showAll: true, actions: noActions)
            case .head:
                ExpandedWeek(vm: app.vm, week: week, showAll: false, actions: noActions)
            case .strips:
                StripWeek(vm: app.vm, week: week, actions: noActions)
            case .list:
                // 清單樣式是小月曆加下面的行程卡，這裡只畫小月曆的一列
                HStack(spacing: 0) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { col, day in
                        MiniCell(vm: app.vm, week: week, col: col, day: day)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, DT.Space.s3)
                .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
            }
            Text("範例行程")
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(Theme.sub)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("月曆樣式預覽：用範例行程畫的一週，會跟著你點的樣式換")
    }
}

/// 主題選擇頁的一列：那款主題的底色與主色、名稱、四個類別色。使用中的打勾，沒買的有鎖頭，試看中的寫「試看中」。
struct ThemeRow: View {
    let palette: ThemePalette
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s3) {
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .fill(palette.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .strokeBorder(palette.separator, lineWidth: DT.Size.hairline)
                    )
                    .overlay(Circle().fill(palette.accent).frame(width: 22, height: 22))
                    .frame(width: DT.Size.touch, height: DT.Size.touch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.name)
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                    Text(palette.note)
                        .dFont(DT.TypeScale.footnote)
                        .foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Grid.gap) {
                    ForEach(Array(palette.categoryColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                    }
                }
                status
            }
            .padding(.vertical, DT.Space.s2)
            .frame(minHeight: DT.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(palette.name)，\(palette.note)\(isLocked ? "，未解鎖" : "")\(isLocked && isSelected ? "，試看中" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var status: some View {
        if isLocked && isSelected {
            Text("試看中")
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.strong)
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .frame(width: 20)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .opacity(isSelected ? 1 : 0)
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

    /// 沒指定類別的行事曆會歸到哪一類。跟 Classifier 的規則一致：有「行程」就是行程，否則第一個。
    private var defaultCategoryID: String {
        settings.value.category(id: AppSettings.fallbackCategoryID).id
    }

    private var currentTag: String {
        let id = calendar.calendarIdentifier
        let s = settings.value
        if s.hiddenCalendarIDs.contains(id) { return Self.hiddenTag }
        if s.holidayCalendarIDs.contains(id) { return Self.holidayTag }
        if let cat = s.calendarCategory[id], s.categories.contains(where: { $0.id == cat }) { return cat }
        return defaultCategoryID
    }

    private var currentText: String {
        switch currentTag {
        case Self.hiddenTag: return "不顯示"
        case Self.holidayTag: return "節日"
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
                    ForEach(settings.value.categories) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                    Text("節日（日期下的小字）").tag(Self.holidayTag)
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
    let canUseCustomColor: Bool
    let needFullVersion: () -> Void

    /// 選色的那一排有沒有打開
    @State private var showColors = false
    /// 選色那一排每個色點的大小
    private static let swatch: CGFloat = 28

    private var colorHex: String {
        index.map { settings.value.categories[$0].colorHex } ?? ""
    }

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
        VStack(spacing: 0) {
            mainRow
            if showColors { colorRow }
        }
        .padding(.vertical, DT.Space.s1)
    }

    /// 選色：先列預設的幾色（會跟著主題換），最後是自訂顏色。沒買的人自訂那一格是鎖頭。
    private var colorRow: some View {
        HStack(spacing: DT.Space.s1) {
            ForEach(FullVersionAccess.presetCategoryHexes, id: \.self) { hex in
                let isCurrent = hex.caseInsensitiveCompare(colorHex) == .orderedSame
                Button {
                    change { $0.colorHex = hex }
                } label: {
                    Circle()
                        .fill(Theme.category(hex: hex).fill)
                        .frame(width: Self.swatch, height: Self.swatch)
                        .overlay {
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.category(hex: hex).on)
                            }
                        }
                        .frame(width: DT.Size.touch, height: DT.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("預設顏色")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if canUseCustomColor {
                ColorPicker("自訂顏色", selection: color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(minWidth: DT.Size.touch, minHeight: DT.Size.touch)
            } else {
                Button(action: needFullVersion) {
                    HStack(spacing: DT.Space.s1) {
                        Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold))
                        Text("自訂顏色").dFont(DT.TypeScale.footnote)
                    }
                    .foregroundStyle(Theme.sub)
                    .frame(minHeight: DT.Size.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("自訂顏色，要完整版")
            }
        }
        .padding(.bottom, DT.Space.s1)
    }

    private var mainRow: some View {
        HStack(spacing: DT.Space.s3) {
            Button {
                showColors.toggle()
            } label: {
                Circle()
                    .fill(Theme.category(hex: colorHex).fill)
                    .frame(width: Self.swatch, height: Self.swatch)
                    .frame(width: DT.Size.touch, height: DT.Size.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("改顏色")
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
        .frame(minHeight: DT.Size.row)
    }
}
