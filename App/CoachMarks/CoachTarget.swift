import SwiftUI

/// 被照亮的元件把自己的位置往上回報，根畫面收齊後交給遮罩
struct CoachTargetKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 讓這個元件可以被引導照亮。active 給 false 時不回報（例：一排日期裡只有今天要回報）。
    func coachTarget(_ id: String, when active: Bool = true) -> some View {
        anchorPreference(key: CoachTargetKey.self, value: .bounds) { anchor in
            active ? [id: anchor] : [:]
        }
    }
}
