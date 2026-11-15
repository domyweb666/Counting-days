import SwiftUI
import EventKit

@main
struct SuanRiZiApp: App {
    @State private var app = AppModel()
    @State private var coach = CoachController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(coach)
                .tint(Theme.accent)
        }
    }
}

/// 依行事曆權限決定顯示哪一頁
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.store.status {
            case .fullAccess:
                CalendarScreen()
            case .notDetermined:
                PermissionIntroView()
            default:
                PermissionDeniedView()
            }
        }
        .overlayPreferenceValue(CoachTargetKey.self) { anchors in
            CoachOverlay(anchors: anchors)
        }
        .modifier(CoachDirector())
        .onChange(of: scenePhase) { _, phase in
            // 使用者可能剛從「設定」改完權限回來
            if phase == .active { app.store.refreshStatus() }
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
                point("行程不會離開這支手機，蒜日子沒有帳號，也沒有伺服器。")
            }
            Spacer()
            if let message = app.store.lastError {
                Text(message).dFont(DT.TypeScale.footnote).foregroundStyle(Theme.destructive)
            }
            WideButton(title: asking ? "等你在視窗上選擇…" : "允許讀取行事曆") {
                asking = true
                Task {
                    await app.store.requestAccess()
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
