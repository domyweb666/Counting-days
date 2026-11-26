import SwiftUI
import EventKit
import WidgetKit
import CalendarCore

@main
struct SuanRiZiApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

/// 小工具畫的東西看這三樣，其中一樣變了就要請它重畫。
/// 買了沒小工具會自己問 App Store，這裡只是買完、退款時請它馬上重畫，不把結果交給它。
private struct WidgetSource: Equatable {
    let changeToken: Int
    let settings: AppSettings
    let isUnlocked: Bool
}

/// 依行事曆權限決定顯示哪一頁
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// 等購買驗證等太久，不等了
    @State private var stoppedWaiting = false
    /// 變動停下來多久才請小工具重畫（秒）。拖選色器時一秒會變很多次，只在停下來之後請一次。
    private let widgetReloadDelay: Double = 0.5

    /// 存下來的設定用到付費的東西，而購買還沒驗完：先不畫，免得已經買的人看到一瞬間沒買的樣子
    private var isWaitingForPurchase: Bool {
        app.settings.usesPaidContent && !app.purchase.hasChecked && !stoppedWaiting
    }

    var body: some View {
        Group {
            if isWaitingForPurchase {
                // 跟啟動畫面同一個底色，看起來像還在開。這裡還不知道該用哪款主題，所以不拿 Theme 的顏色。
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .task {
                        try? await Task.sleep(for: .seconds(PurchaseStore.launchWait))
                        stoppedWaiting = true
                    }
            } else {
                switch app.store.status {
                case .fullAccess:
                    CalendarScreen()
                case .notDetermined:
                    PermissionIntroView()
                default:
                    PermissionDeniedView()
                }
            }
        }
        // 放在畫面裡讀主色，換主題時才會跟著重畫
        .tint(Theme.accent)
        // 設定裡選的外觀（跟隨系統／淺色／深色），開 app 時先套一次
        .onAppear { Appearance.stored.apply() }
        .onChange(of: scenePhase) { _, phase in
            // 使用者可能剛從「設定」改完權限回來
            if phase == .active { app.store.refreshStatus() }
        }
        // 打開蒜日子、行事曆有變動、改了設定，都請小工具重畫
        .task(id: WidgetSource(changeToken: app.store.changeToken, settings: app.settings.value, isUnlocked: app.purchase.isUnlocked)) {
            try? await Task.sleep(for: .seconds(widgetReloadDelay))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onOpenURL { url in
            if WidgetLink.opensToday(url) {
                app.vm.openFromWidget()
            } else if WidgetLink.opensNewEvent(url) {
                app.vm.openNewEventFromControl()
            }
        }
    }
}

/// 第一次打開：先說明為什麼需要行事曆，再跳系統的權限視窗
struct PermissionIntroView: View {
    @Environment(AppModel.self) private var app
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s6) {
            Spacer()
            VStack(alignment: .leading, spacing: DT.Space.s3) {
                Text("蒜日子").dFont(DT.TypeScale.largeTitle).foregroundStyle(Theme.ink)
                Text("把 iPhone 行事曆裡的行程，換成手機上看得清楚的月曆。")
                    .dFont(DT.TypeScale.title3)
                    .foregroundStyle(Theme.ink)
            }
            SectionCard {
                point("需要讀取你的行事曆，才能把行程畫出來。")
                Hairline()
                point("新增和修改行程時，會直接寫回系統行事曆。")
                Hairline()
                point("蒜日子沒有帳號，也沒有自己的伺服器。行程只有在你自己按「分享」的時候，才會傳給你選的人。")
            }
            Spacer()
            if let message = app.store.lastError {
                Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
            }
            WideButton(title: asking ? "等你在視窗上選擇…" : "繼續") {
                asking = true
                Task {
                    await app.store.requestAccess()
                    #if DEBUG
                    DemoSeeder.runIfAsked(store: app.store, settings: app.settings)
                    #endif
                    asking = false
                }
            }
            .disabled(asking)
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.vertical, DT.Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DT.Space.s3) {
            Circle().fill(Theme.accent).frame(width: Theme.Grid.pip, height: Theme.Grid.pip)
            Text(text)
                .dFont(DT.TypeScale.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DT.Space.s3)
        .frame(minHeight: DT.Size.row)
    }
}

/// 權限被拒絕，或只給了「僅新增」：說明要到設定開啟
struct PermissionDeniedView: View {
    @Environment(AppModel.self) private var app

    private var reason: String {
        switch app.store.status {
        case .writeOnly:
            return "目前只允許「加入行程」，蒜日子讀不到既有的行程。請到設定把行事曆權限改成「完整取用權限」。"
        case .restricted:
            return "這支手機的行事曆權限被限制了（例如螢幕使用時間或裝置管理），蒜日子沒辦法讀取行程。"
        default:
            return "蒜日子沒有行事曆權限，所以畫不出任何行程。請到設定把行事曆權限改成「完整取用權限」。"
        }
    }

    var body: some View {
        VStack(spacing: DT.Space.s4) {
            Spacer()
            EmptyStateView(systemImage: "calendar.badge.exclamationmark", title: "讀不到行事曆", message: reason)
            Spacer()
            WideButton(title: "前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(.horizontal, DT.Size.screenMargin)
        .padding(.vertical, DT.Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
