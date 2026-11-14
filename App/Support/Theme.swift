import SwiftUI
import UIKit

// 介面的顏色、字級、間距、圓角一律來自 App/Design/DomyTokens.swift（從 domy-design 複製，不要手改）。
// 這個檔只做兩件事：指定蒜日子的產品色，以及放月曆格子專用、設計系統沒有的值。

typealias DT = DomyTokens

enum Theme {
    /// 蒜日子的產品色：鼠尾草
    static let product = DomyTheme.sage

    static let bg = product.canvas
    static let card = DT.Neutral.surface
    static let muted = DT.Neutral.surfaceMuted
    static let separator = DT.Neutral.separator
    static let ink = DT.Neutral.textPrimary
    static let sub = DT.Neutral.textSecondary
    static let tertiary = DT.Neutral.textTertiary
    static let accent = product.accent
    static let onAccent = product.onAccent
    static let strong = product.strong
    static let soft = product.soft
    static let destructive = DT.Neutral.destructive

    // MARK: 類別色（蒜日子自己功能的顏色，不放進 domy-design）

    /// 預設四個類別的降彩實色：淺色模式的色碼 → 深色模式的色碼
    private static let categoryDark: [UInt32: UInt32] = [
        0x6F5F8F: 0xA99BD0, // 工作 霧紫
        0x4B6C8F: 0x8FB0D4, // 行程 灰藍
        0xA65F45: 0xDB9C84, // 看診 陶土
        0x7A6A3A: 0xC2B078  // 辦事 橄欖褐
    ]
    private static let onKnownCategory = Color(domyLight: 0xFFFFFF, domyDark: 0x1D1D1F)
    private static let fallbackCategoryHex: UInt32 = 0x4B6C8F

    static func parseHex(_ hex: String) -> UInt32? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        return UInt32(s, radix: 16)
    }

    /// 類別色塊的底色與壓在上面的字色。
    /// 預設色在深色模式會換成較亮的版本配深色字；使用者自訂的顏色兩種模式都用同一個色、配白字。
    static func category(hex: String) -> (fill: Color, on: Color) {
        let value = parseHex(hex) ?? fallbackCategoryHex
        if let dark = categoryDark[value] {
            return (Color(domyLight: value, domyDark: dark), onKnownCategory)
        }
        return (Color(uiColor: UIColor(domyHex: value)), .white)
    }

    // MARK: 月曆格子專用的尺寸（例外：設計系統的階梯放不進 7 欄格子）

    enum Grid {
        /// 月曆左右邊距。一格要塞得下 3 個中文字，用不了設計系統的 20。
        static let margin: CGFloat = 8
        static let gap: CGFloat = 3
        static let dayCircle: CGFloat = 30
        static let dayCircleSmall: CGFloat = 26
        static let band: CGFloat = 36
        static let bandThin: CGFloat = 4
        static let pip: CGFloat = 8
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
