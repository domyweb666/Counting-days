import AppIntents
import SwiftUI
import WidgetKit

// 控制中心（也能放鎖定畫面底下、動作按鈕）的「新增行程」：按下去打開蒜日子、停在今天、新增表單開好。免費，不問買了沒。
// 這個檔要同時編進蒜日子與小工具（project.yml）：openAppWhenRun 的動作是在蒜日子裡面跑的，只編進擴充的話打不開。
// 動作跑在蒜日子裡，所以直接發通知給 AppModel，不走網址。
// 2026-11-26 在模擬器試過茄記「記一行」的做法（回傳 OpenURLIntent(suanrizi://new)）：系統記錄寫收到網址，但沒有打開，
// 表單不會出來；把 openAppWhenRun 關掉則連蒜日子都不開。
// 控制項目是 iOS 18 才有的，蒜日子支援到 17，所以按鈕與動作都標 iOS 18。

extension Notification.Name {
    /// 控制中心按了「新增行程」。只在蒜日子裡面發，AppModel 收
    static let newEventControlPressed = Notification.Name("com.domyweb.countingdays.control.newevent")
}

@available(iOS 18.0, *)
struct NewEventControl: ControlWidget {
    /// 上架後不能改，改了使用者放在控制中心的那一顆會失效
    static let kind = "com.domyweb.countingdays.control.newevent"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: NewEventIntent()) {
                Label("新增行程", systemImage: "calendar.badge.plus")
            }
        }
        .displayName("新增行程")
        .description("打開蒜日子，直接新增今天的行程。")
    }
}

@available(iOS 18.0, *)
struct NewEventIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "新增行程"
    static let description = IntentDescription(stringLiteral: "打開蒜日子，直接新增今天的行程。")
    static let isDiscoverable = true
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .newEventControlPressed, object: nil)
        return .result()
    }
}
