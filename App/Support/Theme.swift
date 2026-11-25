import Observation
import SwiftUI
import UIKit

// 介面的顏色、字級、間距、圓角一律來自 App/Design/DomyTokens.swift（從 domy-design 複製，不要手改）。
// 這個檔只做兩件事：指定蒜日子用哪一款主題的顏色，以及放月曆格子專用、設計系統沒有的值。

typealias DT = DomyTokens

/// 預設類別在某一款主題裡的顏色：淺色模式與深色模式的色碼
struct CategoryPair: Sendable {
    let light: UInt32
    let dark: UInt32
}

/// 一款主題的整組顏色。每個 Color 都帶淺色、深色兩個值，跟著系統外觀切換。
struct ThemePalette: Sendable {
    let id: String
    /// 主題選擇頁上的名稱與一句說明
    let name: String
    let note: String
    let bg: Color
    let card: Color
    let muted: Color
    let separator: Color
    let ink: Color
    let sub: Color
    let tertiary: Color
    let accent: Color
    let onAccent: Color
    let strong: Color
    let soft: Color
    /// 刪除、錯誤訊息、假日紅字共用
    let destructive: Color
    /// 四個預設類別在這款主題裡的顏色。key 是設定裡存的預設色碼（`AppSettings.defaultCategories`）。
    let categories: [UInt32: CategoryPair]
}

extension ThemePalette {
    /// 鼠尾草（免費）。中性色與產品色直接指向設計系統的值。
    static let sage = ThemePalette(
        id: "sage",
        name: "鼠尾草",
        note: "淺灰底，鼠尾草綠",
        bg: DomyTheme.sage.canvas,
        card: DT.Neutral.surface,
        muted: DT.Neutral.surfaceMuted,
        separator: DT.Neutral.separator,
        ink: DT.Neutral.textPrimary,
        sub: DT.Neutral.textSecondary,
        tertiary: DT.Neutral.textTertiary,
        accent: DomyTheme.sage.accent,
        onAccent: DomyTheme.sage.onAccent,
        strong: DomyTheme.sage.strong,
        soft: DomyTheme.sage.soft,
        destructive: DT.Neutral.destructive,
        categories: [
            0x6F5F8F: CategoryPair(light: 0x6F5F8F, dark: 0xA99BD0), // 工作 霧紫
            0x4B6C8F: CategoryPair(light: 0x4B6C8F, dark: 0x8FB0D4), // 生活 灰藍
            0xA65F45: CategoryPair(light: 0xA65F45, dark: 0xDB9C84), // 娛樂 陶土
            0x7A6A3A: CategoryPair(light: 0x7A6A3A, dark: 0xC2B078)  // 休息 橄欖褐
        ]
    )

    // 以下六款的色碼來自主題設計稿，每一組「字壓在底色上」都算過對比。
    // 類別色的 key 固定是設定裡存的預設色碼，順序：工作、生活、娛樂、休息。

    private static func c(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(domyLight: light, domyDark: dark)
    }

    static let hongdou = ThemePalette(
        id: "hongdou",
        name: "紅豆湯",
        note: "米白底，豆沙紅",
        bg: c(0xF6F1EC, 0x161111),
        card: c(0xFFFDFB, 0x221A1A),
        muted: c(0xEDE4DC, 0x302626),
        separator: c(0xE6DBD2, 0x3D3131),
        ink: c(0x2A1F1F, 0xF6EEEC),
        sub: c(0x6B5C5A, 0xB3A3A1),
        tertiary: c(0xA8999A, 0x6E5F5E),
        accent: c(0x96484E, 0xE3A1A5),
        onAccent: c(0xFFFFFF, 0x2E1215),
        strong: c(0x7C383E, 0xF0C4C6),
        soft: c(0xF3E1E0, 0x3D2527),
        destructive: c(0xA3271F, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x5E6A8A, dark: 0xA9B4D6),
            0x4B6C8F: CategoryPair(light: 0x3F7470, dark: 0x8CC4BF),
            0xA65F45: CategoryPair(light: 0xA2562F, dark: 0xE3A482),
            0x7A6A3A: CategoryPair(light: 0x7A6A3A, dark: 0xC9B77E)
        ]
    )

    static let qingci = ThemePalette(
        id: "qingci",
        name: "青瓷",
        note: "冷白底，青綠",
        bg: c(0xEFF4F2, 0x0C1413),
        card: c(0xFFFFFF, 0x152120),
        muted: c(0xE2EAE7, 0x213130),
        separator: c(0xDAE3E0, 0x2C3F3D),
        ink: c(0x17201F, 0xEEF5F3),
        sub: c(0x586664, 0x9FB0AD),
        tertiary: c(0x9AA6A4, 0x5C6D6A),
        accent: c(0x2F6F73, 0x8FCBC9),
        onAccent: c(0xFFFFFF, 0x0B2526),
        strong: c(0x245A5E, 0xB9E1DF),
        soft: c(0xDCEBEA, 0x1C3536),
        destructive: c(0xC4372C, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x5B5F97, dark: 0xA7ABE0),
            0x4B6C8F: CategoryPair(light: 0x3A6EA5, dark: 0x8DB7E6),
            0xA65F45: CategoryPair(light: 0xA8573F, dark: 0xE5A28B),
            0x7A6A3A: CategoryPair(light: 0x6C7440, dark: 0xBFC78A)
        ]
    )

    static let lanran = ThemePalette(
        id: "lanran",
        name: "藍染",
        note: "灰藍底，靛藍",
        bg: c(0xF1F3F8, 0x0B0E1A),
        card: c(0xFFFFFF, 0x151A2B),
        muted: c(0xE4E7F0, 0x20273D),
        separator: c(0xDBDFEA, 0x2B334D),
        ink: c(0x161A2B, 0xEEF0F8),
        sub: c(0x5A6078, 0xA2A9C2),
        tertiary: c(0x9BA0B3, 0x5E6682),
        accent: c(0x34478C, 0xA9B8F0),
        onAccent: c(0xFFFFFF, 0x0F1A40),
        strong: c(0x27376F, 0xCBD5F8),
        soft: c(0xDFE4F5, 0x1F2A52),
        destructive: c(0xC4372C, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x6B5796, dark: 0xB9A8E2),
            0x4B6C8F: CategoryPair(light: 0x2E7482, dark: 0x8CC6D3),
            0xA65F45: CategoryPair(light: 0xB0563A, dark: 0xEBA58D),
            0x7A6A3A: CategoryPair(light: 0x80672B, dark: 0xD2B877)
        ]
    )

    static let shibing = ThemePalette(
        id: "shibing",
        name: "柿餅",
        note: "米色底，柿子橘",
        bg: c(0xF8F2E9, 0x17110B),
        card: c(0xFFFDF9, 0x231A12),
        muted: c(0xEFE5D6, 0x32261B),
        separator: c(0xE8DCCB, 0x403124),
        ink: c(0x2B1E14, 0xF8EFE6),
        sub: c(0x6E5D4E, 0xB8A796),
        tertiary: c(0xAD9E90, 0x705F50),
        accent: c(0xB24A1C, 0xF0A070),
        onAccent: c(0xFFFFFF, 0x3A1503),
        strong: c(0x8F3A14, 0xF7C3A3),
        soft: c(0xFAE3D3, 0x432814),
        destructive: c(0xA3271F, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x5D5A8C, dark: 0xACA9DD),
            0x4B6C8F: CategoryPair(light: 0x3C6E8A, dark: 0x8FBEDA),
            0xA65F45: CategoryPair(light: 0x8C4A6A, dark: 0xDDA0BE),
            0x7A6A3A: CategoryPair(light: 0x5F7040, dark: 0xB4C58F)
        ]
    )

    static let yuni = ThemePalette(
        id: "yuni",
        name: "芋泥",
        note: "淡紫灰底，芋頭紫",
        bg: c(0xF4F2F6, 0x110E15),
        card: c(0xFFFFFF, 0x1C1822),
        muted: c(0xE9E5EE, 0x2A2533),
        separator: c(0xE0DBE6, 0x373142),
        ink: c(0x1F1A26, 0xF3EFF8),
        sub: c(0x635C6E, 0xACA4BA),
        tertiary: c(0xA39DAD, 0x665E73),
        accent: c(0x6E5494, 0xC5AEEA),
        onAccent: c(0xFFFFFF, 0x22143A),
        strong: c(0x59427B, 0xDDCEF5),
        soft: c(0xEAE2F4, 0x2E2444),
        destructive: c(0xC4372C, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x46688F, dark: 0x93B5DC),
            0x4B6C8F: CategoryPair(light: 0x3E7566, dark: 0x8CC9B8),
            0xA65F45: CategoryPair(light: 0xA85A52, dark: 0xE6A49C),
            0x7A6A3A: CategoryPair(light: 0x806A2E, dark: 0xD1BC7C)
        ]
    )

    static let shuimo = ThemePalette(
        id: "shuimo",
        name: "水墨",
        note: "宣紙底，黑字朱點",
        bg: c(0xF4F2ED, 0x0E0E0D),
        card: c(0xFCFBF8, 0x1A1A18),
        muted: c(0xE9E6DF, 0x282826),
        separator: c(0xDEDAD1, 0x363633),
        ink: c(0x1A1A1A, 0xF2F0EB),
        sub: c(0x5F5C56, 0xA8A59D),
        tertiary: c(0xA5A198, 0x62605A),
        accent: c(0x1F1F1F, 0xF2F0EB),
        onAccent: c(0xFFFFFF, 0x1A1A18),
        strong: c(0x1A1A1A, 0xFFFFFF),
        soft: c(0xE3DFD6, 0x2E2D2A),
        destructive: c(0xC4372C, 0xFF6B5E),
        categories: [
            0x6F5F8F: CategoryPair(light: 0x3D4A5C, dark: 0x9FB0C8),
            0x4B6C8F: CategoryPair(light: 0x5A6B4F, dark: 0xA9BD9C),
            0xA65F45: CategoryPair(light: 0xA63D2F, dark: 0xEC8F80),
            0x7A6A3A: CategoryPair(light: 0x7A6548, dark: 0xCDB592)
        ]
    )

    /// 主題選擇頁的順序
    static let all: [ThemePalette] = [.sage, .hongdou, .qingci, .lanran, .shibing, .yuni, .shuimo]

    /// 設定裡存的名字不認得（舊版、資料壞掉）就用鼠尾草
    static func find(_ id: String) -> ThemePalette {
        all.first { $0.id == id } ?? .sage
    }

    /// 四個預設類別在這款主題裡的顏色，順序是工作、生活、娛樂、休息
    var categoryColors: [Color] {
        Theme.defaultCategoryKeys
            .compactMap { categories[$0] }
            .map { Color(domyLight: $0.light, domyDark: $0.dark) }
    }
}

/// 目前用哪一款主題。畫面在讀 `Theme` 的顏色時會登記到這裡，換主題後自己重畫。
/// 只由 `SettingsStore` 依設定寫入。
@Observable
final class ThemeState {
    static let shared = ThemeState()
    var palette = ThemePalette.sage
}

enum Theme {
    /// 目前使用的主題
    static var current: ThemePalette { ThemeState.shared.palette }

    /// 預設四個類別在設定裡存的色碼：工作、生活、娛樂、休息
    static let defaultCategoryKeys: [UInt32] = [0x6F5F8F, 0x4B6C8F, 0xA65F45, 0x7A6A3A]

    static var bg: Color { current.bg }
    static var card: Color { current.card }
    static var muted: Color { current.muted }
    static var separator: Color { current.separator }
    static var ink: Color { current.ink }
    static var sub: Color { current.sub }
    static var tertiary: Color { current.tertiary }
    static var accent: Color { current.accent }
    static var onAccent: Color { current.onAccent }
    static var strong: Color { current.strong }
    static var soft: Color { current.soft }
    static var destructive: Color { current.destructive }
    /// 側邊欄打開時，蓋在後面畫面上的暗幕。七款主題共用，不跟著主題換。
    static let scrim = Color.black.opacity(0.35)

    // MARK: 類別色（蒜日子自己功能的顏色，不放進 domy-design）

    private static let onKnownCategory = Color(domyLight: 0xFFFFFF, domyDark: 0x1D1D1F)
    private static let fallbackCategoryHex: UInt32 = 0x4B6C8F

    static func parseHex(_ hex: String) -> UInt32? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        return UInt32(s, radix: 16)
    }

    /// 類別色塊的底色與壓在上面的字色。
    /// 預設色照目前主題的那一組畫，深色模式是較亮的版本配深色字；使用者自訂的顏色兩種模式都用同一個色、配白字。
    static func category(hex: String) -> (fill: Color, on: Color) {
        let value = parseHex(hex) ?? fallbackCategoryHex
        if let pair = current.categories[value] {
            return (Color(domyLight: pair.light, domyDark: pair.dark), onKnownCategory)
        }
        return (Color(uiColor: UIColor(domyHex: value)), .white)
    }

    // MARK: 動畫（按壓的數字在 DT.Motion；其他畫面的動畫都從這裡拿，不各自寫秒數）

    enum Motion {
        // 每一格都寫明秒數：系統預設是 0.5 秒，展開一天會覺得慢
        /// 小變化：展開收合、一列出現或消失、換月。用不會彈的，展開時下面的週才不會跟著晃
        static let change = Animation.smooth(duration: 0.22)
        /// 整塊換掉、滑進滑出：切換檢視、月曆捲到另一天、時間軸換頁
        static let transition = Animation.smooth(duration: 0.3)
        /// 側邊欄開關。常開常關，要比 transition 快
        static let sideMenu = Animation.smooth(duration: 0.22)
    }

    // MARK: 月曆格子專用的尺寸（例外：設計系統的階梯放不進 7 欄格子）

    enum Grid {
        /// 月曆左右邊距。一格要塞得下 3 個中文字，用不了設計系統的 20。
        static let margin: CGFloat = 8
        static let gap: CGFloat = 3
        static let dayCircle: CGFloat = 30
        static let dayCircleSmall: CGFloat = 26
        static let band: CGFloat = 36
        static let pip: CGFloat = 8
        /// 不寫字的跨日細條，跟單日小色塊一樣粗
        static let bandThin: CGFloat = pip
        static let dot: CGFloat = 6
        static let square: CGFloat = 10
        static let ring: CGFloat = 3
    }
}

extension Color {
    /// "#6F5F8F" 這種字串。格式不對時回傳 nil。
    init?(hex: String) {
        guard let v = Theme.parseHex(hex) else { return nil }
        self.init(uiColor: UIColor(domyHex: v))
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#4B6C8F" }
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// 月曆格子裡的小字：設計系統字級以外的尺寸，跟著系統字體大小縮放
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// 月曆格子專用。一般介面文字請用 dFont。
    func sFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }

    /// 設計系統的字級
    func dFont(_ style: DomyTypeStyle) -> some View {
        font(style.font)
    }

    func domyShadow(_ s: DomyShadow) -> some View {
        shadow(color: DT.Neutral.shadow.opacity(s.opacity), radius: s.radius, x: 0, y: s.y)
    }
}

/// 一排裡面有的固定寬、有的按比例分寬度（週條用）
struct FlexWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    /// weight 為 0 表示用自己的寬度
    func flex(_ weight: CGFloat) -> some View {
        layoutValue(key: FlexWeight.self, value: weight)
    }
}

struct FlexRow: Layout {
    var spacing: CGFloat = DT.Space.s1

    private func widths(total: CGFloat, subviews: Subviews) -> [CGFloat] {
        var fixed: CGFloat = 0
        var weightSum: CGFloat = 0
        var natural: [CGFloat] = []
        for s in subviews {
            let w = s[FlexWeight.self]
            if w > 0 {
                weightSum += w
                natural.append(0)
            } else {
                let n = s.sizeThatFits(.unspecified).width
                fixed += n
                natural.append(n)
            }
        }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let remaining = max(total - fixed - gaps, 0)
        return subviews.indices.map { i in
            let w = subviews[i][FlexWeight.self]
            return w > 0 && weightSum > 0 ? remaining * w / weightSum : natural[i]
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 320
        let ws = widths(total: total, subviews: subviews)
        var height: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            height = max(height, s.sizeThatFits(ProposedViewSize(width: ws[i], height: nil)).height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(total: bounds.width, subviews: subviews)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            s.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: ws[i], height: bounds.height)
            )
            x += ws[i] + spacing
        }
    }
}
