import SwiftUI

/// 引導的一步：照亮哪個元件、說明卡寫什麼
struct CoachStep: Identifiable, Equatable {
    let id: String
    /// 要照亮的元件代號，對應畫面上的 .coachTarget("...")
    let targetID: String
    let title: String
    let body: String
    /// 洞比目標外擴多少
    var holePadding: CGFloat = CoachStyle.holePadding
    /// 洞的圓角。超過洞高的一半時會自動縮成一半，所以膠囊和圓鈕給很大的值就好
    var holeCornerRadius: CGFloat = CoachStyle.holeCornerRadius
}

/// 畫面上可以被照亮的元件代號
enum CoachTargetID {
    static let viewTabs = "main.viewTabs"
    static let today = "main.today"
    static let settings = "main.settings"
    static let monthTitle = "main.monthTitle"
}

/// 步驟表。新增或調整步驟只改這個陣列。
enum CoachTour {
    static let steps: [CoachStep] = [
        CoachStep(
            id: "intro",
            targetID: CoachTargetID.viewTabs,
            title: "嗨，我是蒜頭",
            body: "這排可以換看法：整個月、接下來的行程，或一天一天看。",
            holeCornerRadius: CoachStyle.roundHole
        ),
        CoachStep(
            id: "day",
            targetID: CoachTargetID.today,
            title: "點一天看行程",
            body: "點任何一天，下面會列出當天的行程。長按可以新增。",
            holePadding: 4
        ),
        CoachStep(
            id: "settings",
            targetID: CoachTargetID.settings,
            title: "樣式和顏色在這裡",
            body: "月曆有四種樣式。每本行事曆也可以分類別、換顏色。",
            holeCornerRadius: CoachStyle.roundHole
        ),
        CoachStep(
            id: "month",
            targetID: CoachTargetID.monthTitle,
            title: "開始吧",
            body: "點月份可以跳到任何年月。想再看一次教學，到設定裡找。"
        )
    ]
}

/// 引導的所有數值集中在這裡
enum CoachStyle {
    /// 進入主畫面後多久開始
    static let startDelay: Double = 0.4
    /// 目標元件一直沒出現時，等多久自動跳下一步
    static let missingTargetWait: Double = 0.6

    static let dimLight: Double = 0.55
    static let dimDark: Double = 0.65
    static let fade: Double = 0.25

    static let holePadding: CGFloat = 8
    static let holeCornerRadius: CGFloat = 16
    /// 膠囊與圓鈕用：一定會被縮成洞高的一半
    static let roundHole: CGFloat = 999
    static let glowWidth: CGFloat = 3
    static let glowRadius: CGFloat = 12
    static let glowOpacity: Double = 0.8
    static let holeSpring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// 減少動態效果時，洞先蓋掉再露出來
    static let holeFadeOut: Double = 0.12
    static let holeFadeIn: Double = 0.18

    static let cardMargin: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let cardFadeIn: Double = 0.18
    /// 卡片高度上限佔畫面的比例
    static let cardMaxHeightRatio: CGFloat = 0.4
    /// 卡片裡內文以外的部分（頭像、標題、按鈕、留白）大約佔的高度
    static let cardChrome: CGFloat = 150
    static let cardBodyMinHeight: CGFloat = 80
    static let avatar: CGFloat = 36

    static let typeInterval: Double = 0.03
    static let punctuationPause: Double = 0.12
    static let punctuation: Set<Character> = ["，", "。", "、", "！", "？", "；", "："]

    static let dot: CGFloat = 5
    static let dotGap: CGFloat = 4
    static let dotCurrent: CGFloat = 14

    static let buttonHeight: CGFloat = 36
    static let skipTop: CGFloat = 8
    static let skipTrailing: CGFloat = 16
    static let skipFill: Double = 0.45
}
