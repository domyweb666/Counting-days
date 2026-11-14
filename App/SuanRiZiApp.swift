import SwiftUI
import EventKit

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
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("蒜日子").sFont(34, .black).foregroundStyle(Theme.ink)
            Text("把 iPhone 行事曆裡的行程，換成手機上看得清楚的月曆。")
                .sFont(19, .bold)
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 10) {
                point("需要讀取你的行事曆，才能把行程畫出來。")
                point("新增和修改行程時，會直接寫回系統行事曆。")
                point("行程不會離開這支手機，蒜日子沒有帳號，也沒有伺服器。")
            }
            Spacer()
            Button {
                asking = true
                Task {
                    await app.store.requestAccess()
                    asking = false
                }
            } label: {
                Text("允許讀取行事曆")
                    .sFont(17, .bold)
                    .foregroundStyle(Theme.inkInverse)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .disabled(asking)
            if let message = app.store.lastError {
                Text(message).sFont(13, .bold).foregroundStyle(Theme.holiday)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.select).frame(width: 10, height: 10)
            Text(text).sFont(16, .medium).foregroundStyle(Theme.pastFg)
        }
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
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("讀不到行事曆").sFont(28, .black).foregroundStyle(Theme.ink)
            Text(reason).sFont(16, .medium).foregroundStyle(Theme.pastFg)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("前往設定")
                    .sFont(17, .bold)
                    .foregroundStyle(Theme.inkInverse)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg.ignoresSafeArea())
    }
}
