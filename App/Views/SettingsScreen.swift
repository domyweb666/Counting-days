import SwiftUI
import EventKit
import CalendarCore

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @State private var showCategories = false
    @State private var showThemes = false
    @State private var showModes = false
    /// 正在看哪一本行事曆的詳情
    @State private var detailCalendarID: String?
    @State private var showAddCalendar = false
    @State private var showCalendarOrder = false
    @State private var showTimeZones = false
    @State private var showFullVersion = false
    @State private var showFamily = false
    @State private var showMail = false
    /// 上方跳一下的提示（例：已複製版本資訊）
    @State private var toast: String?

    private var settings: SettingsStore { app.settings }
    private let config = VeggieConfig.current
    /// 提示停多久
    private let toastSeconds: Double = 2

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
                // 順序照《蔬菜家族 App 共用基本元素規格》：蒜日子自己的 → 一般 → 購買 → 支援 → 關於 → 頁尾
                displaySection
                // 天氣還沒做完，開了也不會有東西，先不放 weatherSection。做完第 8 片再放回來。
                calendarSection
                categoryLink
                countdownSection
                generalSection
                purchaseSection
                supportSection
                aboutSection
                VeggieFooter(show: show)
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
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .dFont(DT.TypeScale.callout)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, DT.Space.s4)
                    .padding(.vertical, DT.Space.s2)
                    .background(Capsule().fill(Theme.card))
                    .domyShadow(DT.Elevation.level1)
                    .padding(.top, DT.Space.s2)
                    .transition(.opacity)
            }
        }
    }

    /// 上方跳一下提示，過一會兒自己收起來
    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            do {
                try await Task.sleep(for: .seconds(toastSeconds))
            } catch {
                // 只有畫面離開、工作被取消才會到這裡，提示跟著畫面一起消失
                return
            }
            withAnimation {
                if toast == text { toast = nil }
            }
        }
    }

    // MARK: 顯示

    private var displaySection: some View {
        SectionCard(title: "顯示") {
            Button {
                showThemes = true
            } label: {
                VeggieRow(icon: "paintpalette", title: "主題", value: Theme.current.name, accessory: .push)
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
                VeggieRow(icon: "calendar", title: "月曆樣式", value: settings.effectiveMode.label, accessory: .push)
            }
            .buttonStyle(PressStyle())
            .sheet(isPresented: $showModes) {
                DisplayModeSettingsScreen()
            }
            Hairline()
            SettingsRow(label: "一週從哪天開始", icon: "arrow.left.arrow.right") {
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
            SettingsRow(label: "顯示農曆與節氣", icon: "moon") {
                Toggle("顯示農曆與節氣", isOn: settings.binding(\.showLunar))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
        }
    }

    // MARK: 一般

    private var generalSection: some View {
        let usesDevice = settings.value.usesDeviceTimeZone
        let zoneName = TimeZoneSettingsScreen.name(of: settings.value.effectiveTimeZone(device: .current))
        let usesDeviceBinding = Binding(
            get: { settings.value.usesDeviceTimeZone },
            set: { on in
                settings.update { s in
                    s.usesDeviceTimeZone = on
                    // 第一次關掉時先帶入手機現在的時區，下面那一列才有東西可以顯示
                    if !on, s.timeZoneID == nil { s.timeZoneID = TimeZone.current.identifier }
                }
            }
        )
        return SectionCard(
            title: "一般",
            footer: usesDevice
                ? "月曆跟著 iPhone 的時區。出國時想照家裡的時間看行程，可以關掉自己選。"
                : "月曆照選的時區排日期和時間。新增、修改行程的畫面是 iPhone 內建的，上面的時間還是照手機的時區。"
        ) {
            Menu {
                Picker(VeggieText.appearance, selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                VeggieRow(icon: "circle.lefthalf.filled", title: VeggieText.appearance, value: appearance.title, accessory: .push)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(VeggieText.appearance)：\(appearance.title)")
            Hairline()
            SettingsRow(label: "使用裝置時區", icon: "clock") {
                Toggle("使用裝置時區", isOn: usesDeviceBinding)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            Hairline()
            Button {
                showTimeZones = true
            } label: {
                VeggieRow(icon: "globe", title: "時區", value: zoneName, accessory: .push)
            }
            .buttonStyle(PressStyle())
            .disabled(usesDevice)
            .opacity(usesDevice ? 0.5 : 1)
            .accessibilityLabel("時區：\(zoneName)")
        }
        .sheet(isPresented: $showTimeZones) {
            TimeZoneSettingsScreen()
        }
        .onChange(of: appearance) { _, chosen in
            chosen.apply()
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
        let shown = app.vm.shownCalendars
        return SectionCard(
            title: "行事曆",
            footer: "這裡只列有加入蒜日子的行事曆。點一本可以改它歸哪個類別、當成節日，或從蒜日子移除。這些都只改蒜日子的顯示方式，不會動到系統行事曆。"
        ) {
            if shown.isEmpty {
                SettingsRow(label: app.store.calendars.isEmpty ? "這支手機還沒有任何行事曆" : "還沒有加入任何行事曆") { EmptyView() }
                Hairline()
            }
            ForEach(shown, id: \.calendarIdentifier) { cal in
                CalendarRoleRow(settings: settings, calendar: cal) {
                    detailCalendarID = cal.calendarIdentifier
                }
                Hairline()
            }
            Button {
                showAddCalendar = true
            } label: {
                VeggieRow(icon: "plus.circle", title: "加入行事曆", accessory: .push)
            }
            .buttonStyle(PressStyle())
            if shown.count > 1 {
                Hairline()
                Button {
                    showCalendarOrder = true
                } label: {
                    VeggieRow(icon: "arrow.up.arrow.down", title: "行事曆顯示順序", accessory: .push)
                }
                .buttonStyle(PressStyle())
            }
        }
        .sheet(isPresented: $showCalendarOrder) {
            CalendarOrderScreen()
        }
        .sheet(isPresented: Binding(
            get: { detailCalendarID != nil },
            set: { isShown in if !isShown { detailCalendarID = nil } }
        )) {
            if let id = detailCalendarID {
                CalendarDetailScreen(calendarID: id)
            }
        }
        .sheet(isPresented: $showAddCalendar) {
            AddCalendarScreen()
        }
    }

    // MARK: 類別（收在第二頁）

    private var categoryLink: some View {
        SectionCard(footer: "改類別的名稱、顏色，或指定哪一類優先當主事件。") {
            Button {
                showCategories = true
            } label: {
                VeggieRow(icon: "tag", title: "類別與顏色", accessory: .push)
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

    // MARK: 購買

    private var purchaseSection: some View {
        let purchase = app.purchase
        return VStack(alignment: .leading, spacing: DT.Space.s2) {
            SectionCard(title: "購買") {
                Button {
                    showFullVersion = true
                } label: {
                    VeggieRow(
                        icon: "sparkles",
                        title: "蒜日子完整版",
                        value: purchase.isUnlocked ? "已解鎖" : nil,
                        accessory: .push
                    )
                }
                .buttonStyle(PressStyle())
                Hairline()
                // 只是多一個入口，做的事跟完整版頁上的「恢復購買」一樣；「買了沒」還是 PurchaseStore 在算
                Button {
                    Task { await purchase.restore() }
                } label: {
                    VeggieRow(icon: "arrow.clockwise", title: VeggieText.restore, value: purchase.isBusy ? "恢復中…" : nil)
                }
                .buttonStyle(PressStyle())
                .disabled(purchase.isBusy)
            }
            if let message = purchase.message {
                Text(message)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(purchase.messageIsProblem ? Theme.destructive : Theme.sub)
                    .padding(.horizontal, DT.Space.s4)
            }
        }
        .sheet(isPresented: $showFullVersion) {
            FullVersionSheet(reason: .settings)
        }
    }

    // MARK: 支援

    /// 意見回饋、評分、分享。設定檔沒填的那一列不出現；三列都沒有就整區不出現。
    @ViewBuilder
    private var supportSection: some View {
        if config.supportEmail != nil || config.appStoreURL != nil {
            SectionCard(title: "支援") {
                if let email = config.supportEmail {
                    Button {
                        if Feedback.canUseMailSheet {
                            showMail = true
                        } else if let url = Feedback.mailtoURL(to: email) {
                            openURL(url)
                        }
                    } label: {
                        VeggieRow(icon: "envelope", title: VeggieText.feedback, accessory: .push)
                    }
                    .buttonStyle(PressStyle())
                    .sheet(isPresented: $showMail) {
                        FeedbackMailView(recipient: email) { showMail = false }
                            .ignoresSafeArea()
                    }
                }
                if let reviewURL = config.writeReviewURL, let storeURL = config.appStoreURL {
                    if config.supportEmail != nil { Hairline() }
                    Link(destination: reviewURL) {
                        VeggieRow(icon: "star", title: VeggieText.rate, accessory: .external)
                    }
                    .buttonStyle(PressStyle())
                    Hairline()
                    ShareLink(item: storeURL, message: Text("我在用\(config.name)：\(config.tagline)")) {
                        VeggieRow(icon: "square.and.arrow.up", title: VeggieText.share, accessory: .external)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    // MARK: 關於

    private var aboutSection: some View {
        SectionCard(
            title: "關於",
            footer: "蒜日子直接讀寫 iPhone 的系統行事曆，沒有自己的帳號，也不會把行程傳到任何伺服器。置頂、短名、類別這些設定只存在這支手機。購買完整版由 Apple 處理，蒜日子拿不到你的付款資料。"
        ) {
            if !VeggieApp.others.isEmpty {
                Button {
                    showFamily = true
                } label: {
                    VeggieRow(icon: "leaf", title: VeggieText.family, accessory: .push)
                }
                .buttonStyle(PressStyle())
                .sheet(isPresented: $showFamily) {
                    VeggieFamilyView()
                }
            }
            if let url = config.privacyURL {
                if !VeggieApp.others.isEmpty { Hairline() }
                Link(destination: url) {
                    VeggieRow(icon: "hand.raised", title: VeggieText.privacy, accessory: .external)
                }
                .buttonStyle(PressStyle())
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
    var icon: String?
    var dotColor: Color?
    let trailing: Trailing

    init(label: String, icon: String? = nil, dotColor: Color? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.icon = icon
        self.dotColor = dotColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DT.Space.s3) {
            if let icon {
                VeggieRowIcon(systemName: icon)
            }
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

/// 設定裡一本行事曆的那一列：色點、名稱、現在歸哪一類，右邊一個 ⓘ。整列點了開那本行事曆的詳情。
struct CalendarRoleRow: View {
    let settings: SettingsStore
    let calendar: EKCalendar
    let open: () -> Void

    static let holidayTag = "__holiday__"

    /// 這本行事曆現在的角色：某個類別的識別碼，或是節日。
    /// 沒指定過的歸到預設那一類，跟 Classifier 的規則一致：有「行程」就是行程，否則第一個。
    static func tag(for calendarID: String, in s: AppSettings) -> String {
        if s.holidayCalendarIDs.contains(calendarID) { return holidayTag }
        if let cat = s.calendarCategory[calendarID], s.categories.contains(where: { $0.id == cat }) { return cat }
        return s.category(id: AppSettings.fallbackCategoryID).id
    }

    static func text(for tag: String, in s: AppSettings) -> String {
        tag == holidayTag ? "節日" : s.category(id: tag).name
    }

    var body: some View {
        let s = settings.value
        let text = Self.text(for: Self.tag(for: calendar.calendarIdentifier, in: s), in: s)
        Button(action: open) {
            HStack(spacing: DT.Space.s3) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                Text(calendar.title)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(text)
                    .dFont(DT.TypeScale.callout)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, DT.Space.s2)
            .frame(minHeight: DT.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(calendar.title)：\(text)")
        .accessibilityHint("改類別，或從蒜日子移除")
    }
}

/// 設定的第二頁：一本行事曆。改它歸哪個類別、當成節日，或從蒜日子移除。
struct CalendarDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let calendarID: String

    private var settings: SettingsStore { app.settings }

    private var calendar: EKCalendar? {
        app.store.calendars.first { $0.calendarIdentifier == calendarID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                VStack(alignment: .leading, spacing: DT.Space.s1) {
                    Text(calendar?.title ?? "找不到這本行事曆")
                        .dFont(DT.TypeScale.largeTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let account = calendar?.source?.title, !account.isEmpty {
                        Text(account)
                            .dFont(DT.TypeScale.subheadline)
                            .foregroundStyle(Theme.sub)
                    }
                }
                if calendar == nil {
                    Text("它可能剛從這支手機刪掉了。")
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.sub)
                } else {
                    roleSection
                    removeSection
                }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
    }

    private var roleSection: some View {
        let s = settings.value
        let current = CalendarRoleRow.tag(for: calendarID, in: s)
        return SectionCard(
            title: "顯示成",
            footer: "選一個類別，月曆上就用那個類別的顏色。選「節日」的話，這本行事曆的內容會變成日期下面的小字。"
        ) {
            ForEach(s.categories) { cat in
                choiceRow(cat.name, dot: Theme.category(hex: cat.colorHex).fill, isCurrent: current == cat.id) {
                    setRole(cat.id)
                }
                Hairline()
            }
            choiceRow("節日（日期下的小字）", dot: nil, isCurrent: current == CalendarRoleRow.holidayTag) {
                setRole(CalendarRoleRow.holidayTag)
            }
        }
    }

    private func choiceRow(_ title: String, dot: Color?, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s3) {
                if let dot {
                    Circle().fill(dot).frame(width: Theme.Grid.square, height: Theme.Grid.square)
                }
                Text(title)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isCurrent ? 1 : 0)
            }
            .frame(minHeight: DT.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func setRole(_ tag: String) {
        settings.update { s in
            s.holidayCalendarIDs.remove(calendarID)
            s.calendarCategory.removeValue(forKey: calendarID)
            if tag == CalendarRoleRow.holidayTag {
                s.holidayCalendarIDs.insert(calendarID)
            } else {
                s.calendarCategory[calendarID] = tag
            }
        }
    }

    private var removeSection: some View {
        SectionCard(
            footer: "移除之後，這本行事曆的行程不會出現在蒜日子的月曆、搜尋和倒數日。iPhone 的行事曆 app 和 Google、iCloud 上的資料都不會動，之後可以從「加入行事曆」加回來。"
        ) {
            Button {
                settings.update { $0.hiddenCalendarIDs.insert(calendarID) }
                dismiss()
            } label: {
                Text("從蒜日子移除")
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// 設定的第二頁：選時區。上面可以打字找（城市、時區名稱都找得到）。
struct TimeZoneSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// 清單上的一列
    struct Item: Identifiable {
        let id: String
        let city: String
        let name: String
        let offset: String
        let seconds: Int
    }

    @State private var items: [Item] = []
    @State private var keyword = ""

    private static let locale = Locale(identifier: "zh_Hant_TW")

    /// 「台北標準時間」這種名稱；手機給不出來就用時區代號
    static func name(of zone: TimeZone) -> String {
        zone.localizedName(for: .standard, locale: locale) ?? zone.identifier
    }

    /// 「GMT+8」「GMT+5:30」
    static func offsetText(seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let rest = minutes % 60
        return "GMT\(sign)\(minutes / 60)" + (rest == 0 ? "" : String(format: ":%02d", rest))
    }

    private var shown: [Item] {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return items }
        return items.filter {
            $0.city.localizedCaseInsensitiveContains(key)
                || $0.name.localizedCaseInsensitiveContains(key)
                || $0.id.localizedCaseInsensitiveContains(key)
        }
    }

    var body: some View {
        let currentID = app.settings.value.effectiveTimeZone(device: .current).identifier
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("時區")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                TextField("找城市或時區，例如：東京", text: $keyword)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .padding(.horizontal, DT.Space.s4)
                    .frame(minHeight: DT.Size.field)
                    .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if shown.isEmpty, !items.isEmpty {
                        Text("找不到「\(keyword)」。試試城市的名字。")
                            .dFont(DT.TypeScale.subheadline)
                            .foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, DT.Space.s4)
                    }
                    ForEach(shown) { item in
                        Button {
                            app.settings.update { $0.timeZoneID = item.id }
                            dismiss()
                        } label: {
                            HStack(spacing: DT.Space.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.city)
                                        .dFont(DT.TypeScale.body)
                                        .foregroundStyle(Theme.ink)
                                    Text("\(item.name) · \(item.offset)")
                                        .dFont(DT.TypeScale.footnote)
                                        .foregroundStyle(Theme.sub)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .opacity(item.id == currentID ? 1 : 0)
                            }
                            .padding(.vertical, DT.Space.s2)
                            .frame(minHeight: DT.Size.row)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(item.city)，\(item.name)，\(item.offset)")
                        .accessibilityAddTraits(item.id == currentID ? .isSelected : [])
                        Hairline()
                    }
                }
                .padding(.horizontal, DT.Size.screenMargin)
                .padding(.bottom, DT.Space.s8)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear { if items.isEmpty { items = Self.loadItems() } }
    }

    /// 手機認得的所有時區，照離 GMT 多遠排，同一個時差的照城市名排
    private static func loadItems() -> [Item] {
        // 城市的中文名要靠日期格式的「VVV」取，TimeZone 自己給不出來
        let cityFormatter = DateFormatter()
        cityFormatter.locale = locale
        cityFormatter.dateFormat = "VVV"
        let now = Date()
        return TimeZone.knownTimeZoneIdentifiers
            .compactMap { id -> Item? in
                guard let zone = TimeZone(identifier: id) else { return nil }
                cityFormatter.timeZone = zone
                let seconds = zone.secondsFromGMT(for: now)
                return Item(
                    id: id,
                    city: cityFormatter.string(from: now),
                    name: name(of: zone),
                    offset: offsetText(seconds: seconds),
                    seconds: seconds
                )
            }
            .sorted { a, b in
                if a.seconds != b.seconds { return a.seconds < b.seconds }
                return a.city.localizedStandardCompare(b.city) == .orderedAscending
            }
    }
}

/// 設定的第二頁：拖著排行事曆的順序。
struct CalendarOrderScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DT.Space.s4) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("行事曆顯示順序")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("按住右邊的三條線上下拖。開始時間一樣的行程，排前面的行事曆會顯示在上面。")
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.sub)
                if let message = app.settings.errorMessage {
                    Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
                }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s2)
            // 拖著排用 iPhone 內建的清單，一直開著編輯狀態，右邊才有可以拖的把手
            List {
                ForEach(app.vm.shownCalendars, id: \.calendarIdentifier) { cal in
                    HStack(spacing: DT.Space.s3) {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.title)
                                .dFont(DT.TypeScale.body)
                                .foregroundStyle(Theme.ink)
                            if let account = cal.source?.title, !account.isEmpty {
                                Text(account)
                                    .dFont(DT.TypeScale.footnote)
                                    .foregroundStyle(Theme.sub)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .onMove { source, destination in
                    app.vm.moveShownCalendar(from: source, to: destination)
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
    }
}

/// 設定的第二頁：把移除的行事曆加回來，或建立一本新的。
struct AddCalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newColor = Theme.accent
    /// 建立之後要給使用者看的那句話，以及它是不是壞消息
    @State private var createMessage: String?
    @State private var createFailed = false

    private var settings: SettingsStore { app.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("加入行事曆")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message = settings.errorMessage {
                    Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
                }
                removedSection
                createSection
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
    }

    private var createSection: some View {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: DT.Space.s3) {
            SectionCard(
                title: "建立新的行事曆",
                footer: "會寫進 iPhone 的行事曆：有開 iCloud 行事曆就放在 iCloud，沒有就放在這支手機上。之後要刪掉它，得到 iPhone 的行事曆 app 刪。"
            ) {
                TextField("名稱", text: $newName)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: DT.Size.row)
                    .submitLabel(.done)
                Hairline()
                SettingsRow(label: "顏色") {
                    ColorPicker("顏色", selection: $newColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(minWidth: DT.Size.touch, minHeight: DT.Size.touch)
                }
            }
            if let createMessage {
                Text(createMessage)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(createFailed ? Theme.destructive : Theme.strong)
                    .padding(.horizontal, DT.Space.s4)
            }
            WideButton(title: "建立", kind: .secondary) {
                let problem = app.store.createCalendar(title: name, color: UIColor(newColor).cgColor)
                createFailed = problem != nil
                createMessage = problem ?? "已建立「\(name)」，回設定的清單就看得到。"
                if problem == nil { newName = "" }
            }
            .disabled(name.isEmpty)
            .opacity(name.isEmpty ? 0.5 : 1)
        }
    }

    private var removedSection: some View {
        let removed = app.vm.removedCalendars
        return SectionCard(
            title: "手機上還沒加入的",
            footer: "訂閱行事曆和節日行事曆要到 iPhone 的「行事曆」app 加。加好之後回到蒜日子，它會自動出現在設定的清單裡。"
        ) {
            if removed.isEmpty {
                SettingsRow(label: "手機上的行事曆都已經加入了") { EmptyView() }
            }
            ForEach(Array(removed.enumerated()), id: \.element.calendarIdentifier) { index, cal in
                if index > 0 { Hairline() }
                Button {
                    settings.update { $0.hiddenCalendarIDs.remove(cal.calendarIdentifier) }
                } label: {
                    HStack(spacing: DT.Space.s3) {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.title)
                                .dFont(DT.TypeScale.body)
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            if let account = cal.source?.title, !account.isEmpty {
                                Text(account)
                                    .dFont(DT.TypeScale.footnote)
                                    .foregroundStyle(Theme.sub)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, DT.Space.s2)
                    .frame(minHeight: DT.Size.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("加入 \(cal.title)")
            }
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
