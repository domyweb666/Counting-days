import SwiftUI
import CalendarCore

/// 一步要怎麼進行
enum CoachKind {
    /// 照亮目標，按「知道了」前進
    case plain
    /// 洞裡的元件真的點得到，使用者點了才前進
    case tap
    /// 在目標旁邊畫一個長按選單的示意
    case fakeMenu
    /// 五種檢視一張張看
    case demoViews
    /// 四種月曆樣式一張張看
    case demoStyles
}

/// 引導的一步：照亮哪個元件、說明卡寫什麼
struct CoachStep: Identifiable, Equatable {
    let id: String
    /// 要照亮的元件代號，對應畫面上的 .coachTarget("...")
    let targetID: String
    var kind: CoachKind = .plain
    let title: String
    let body: String
    /// 這一步要把今天的行程展開
    var showsDayPanel = false
    /// 洞比目標外擴多少
    var holePadding: CGFloat = CoachStyle.holePadding
    /// 左右另外指定外擴多少；不給就跟 holePadding 一樣
    var holePaddingX: CGFloat?
    /// 洞的圓角。超過洞高的一半時會自動縮成一半，所以膠囊和圓鈕給很大的值就好
    var holeCornerRadius: CGFloat = CoachStyle.holeCornerRadius

    var isDemo: Bool { kind == .demoViews || kind == .demoStyles }
}

/// 一張張看的時候，每一張的名稱與一句說明
struct CoachDemoItem: Equatable {
    let name: String
    let caption: String
}

/// 畫面上可以被照亮的元件代號
enum CoachTargetID {
    static let menu = "main.menu"
    static let content = "main.content"
    static let today = "main.today"
    static let dayPanel = "main.dayPanel"
    static let firstRow = "main.dayPanel.firstRow"
    static let monthTitle = "main.monthTitle"
}

/// 步驟表。新增或調整步驟只改這裡。
enum CoachTour {
    static let steps: [CoachStep] = [
        CoachStep(
            id: "intro",
            targetID: CoachTargetID.menu,
            title: "嗨，我是蒜頭",
            body: "行程有五種看法，都收在這顆選單裡。帶你一張張看。",
            holeCornerRadius: CoachStyle.roundHole
        ),
        CoachStep(
            id: "views",
            targetID: CoachTargetID.content,
            kind: .demoViews,
            title: "五種看法",
            body: "",
            holePadding: CoachStyle.holePadding,
            holePaddingX: CoachStyle.fullWidthHole
        ),
        CoachStep(
            id: "tap",
            targetID: CoachTargetID.today,
            kind: .tap,
            title: "換你點點看",
            body: "點一下亮起來的今天，看當天有哪些行程。",
            holePadding: 4
        ),
        CoachStep(
            id: "panel",
            targetID: CoachTargetID.dayPanel,
            title: "當天的行程在這裡",
            body: "最重要的那件在最上面，字最大。再點同一天就收起來。",
            showsDayPanel: true,
            holePadding: 4
        ),
        CoachStep(
            id: "hold",
            targetID: CoachTargetID.firstRow,
            kind: .fakeMenu,
            title: "長按有更多",
            body: "長按一件行程，可以置頂、取短名，或加入倒數日。",
            showsDayPanel: true,
            holePadding: 4
        ),
        CoachStep(
            id: "styles",
            targetID: CoachTargetID.content,
            kind: .demoStyles,
            title: "月曆有四種樣式",
            body: "",
            holePadding: CoachStyle.holePadding,
            holePaddingX: CoachStyle.fullWidthHole
        ),
        CoachStep(
            id: "end",
            targetID: CoachTargetID.monthTitle,
            title: "開始吧",
            body: "點月份可以跳到任何年月。想再看一次教學，設定裡有。"
        )
    ]

    static let views: [ViewKind] = [.month, .agenda, .week, .threeDay, .day]
    static let styles: [DisplayMode] = [.flex, .list, .strips, .head]

    static func caption(for view: ViewKind) -> String {
        switch view {
        case .month: return "整個月一眼看完，點一天就展開。"
        case .agenda: return "從今天起，有行程的日子一路往下列。"
        case .week: return "七天排在時間軸上，看哪裡撞期。"
        case .threeDay: return "一次看三天，標題放得下。"
        case .day: return "一天從早到晚。"
        }
    }

    static func caption(for style: DisplayMode) -> String {
        switch style {
        case .flex: return "每件事都寫出來，那一週跟著長高。"
        case .list: return "小月曆用顏色標出哪天有事，下面列出接下來的行程。"
        case .strips: return "沒事的日子縮窄，有事的撐開。"
        case .head: return "每天只寫最重要的一件，其他用小色塊。"
        }
    }

    /// 這種步驟要一張張看哪些東西。不是一張張看的步驟回傳空陣列。
    static func demoItems(for kind: CoachKind) -> [CoachDemoItem] {
        switch kind {
        case .demoViews: return views.map { CoachDemoItem(name: $0.label, caption: caption(for: $0)) }
        case .demoStyles:
            // 付費的樣式照樣演給人看，只在說明後面標出來；引導裡不放購買鈕
            return styles.map { style in
                let note = FullVersionAccess.isFree(style) ? "" : "（完整版）"
                return CoachDemoItem(name: style.label, caption: caption(for: style) + note)
            }
        case .plain, .tap, .fakeMenu: return []
        }
    }
}

/// 引導的所有數值集中在這裡
enum CoachStyle {
    /// 使用者要求開始之後，等多久才開始（讓設定頁先關好）
    static let startDelay: Double = 0.4
    /// 目標元件一直沒出現時，等多久自動跳下一步
    static let missingTargetWait: Double = 2.5
    /// 切回月曆後，等多久再把今天那一週捲回最上面一次；清掉與放回之間隔多久
    static let recenterDelay: Double = 0.15
    static let recenterGap: Double = 0.05

    static let dimLight: Double = 0.55
    static let dimDark: Double = 0.65
    static let fade: Double = 0.25

    static let holePadding: CGFloat = 8
    static let holeCornerRadius: CGFloat = 16
    /// 膠囊與圓鈕用：一定會被縮成洞高的一半
    static let roundHole: CGFloat = 999
    /// 照亮整塊月曆區時，洞的左右開到螢幕外，只看得到上下兩條邊，
    /// 月曆兩側才不會被框線貼住
    static let fullWidthHole: CGFloat = 40
    static let glowWidth: CGFloat = 3
    static let glowRadius: CGFloat = 12
    static let glowOpacity: Double = 0.8
    static let holeSpring = Animation.spring(response: 0.7, dampingFraction: 0.82)
    /// 減少動態效果時，洞先蓋掉再露出來
    static let holeFadeOut: Double = 0.12
    static let holeFadeIn: Double = 0.18
    /// 一張張看的時候，洞的下緣離說明卡多遠
    static let demoGap: CGFloat = 12

    static let cardMargin: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let cardFadeIn: Double = 0.18
    /// 卡片高度上限佔畫面的比例
    static let cardMaxHeightRatio: CGFloat = 0.4
    /// 卡片裡內文以外的部分（頭像、標題、按鈕、留白）大約佔的高度
    static let cardChrome: CGFloat = 150
    static let cardBodyMinHeight: CGFloat = 80
    /// 判斷卡片放上面還是下面時，先當成卡片有這麼高
    static let cardEstimatedHeight: CGFloat = 250
    static let avatar: CGFloat = 36

    static let typeInterval: Double = 0.055
    static let punctuationPause: Double = 0.12
    static let punctuation: Set<Character> = ["，", "。", "、", "！", "？", "；", "："]

    static let dot: CGFloat = 5
    static let dotGap: CGFloat = 4
    static let dotCurrent: CGFloat = 14

    static let buttonHeight: CGFloat = 36
    static let chipHeight: CGFloat = 32
    static let skipTop: CGFloat = 8
    static let skipTrailing: CGFloat = 16
    static let skipFill: Double = 0.45

    /// 長按選單的示意：寬度、離那一列多遠、等多久才出現
    static let fakeMenuWidth: CGFloat = 214
    static let fakeMenuInset: CGFloat = 56
    static let fakeMenuGap: CGFloat = 8
    static let fakeMenuDelay: Double = 0.9
}
