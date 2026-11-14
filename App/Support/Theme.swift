import SwiftUI
import UIKit

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// 淺色、深色模式各一個顏色
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    /// "#6D28D9" 這種字串。格式不對時回傳 nil，由呼叫的地方決定怎麼辦。
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(uiColor: UIColor(rgb: v))
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#1D4ED8" }
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

enum Theme {
    static let bg = Color(light: 0xF4F5F7, dark: 0x0E1014)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1F26)
    static let ink = Color(light: 0x14171C, dark: 0xF2F4F7)
    static let inkInverse = Color(light: 0xFFFFFF, dark: 0x14171C)
    static let sub = Color(light: 0x5B6370, dark: 0xA3ABB8)
    static let pastBg = Color(light: 0xE3E6EB, dark: 0x2A2E37)
    static let pastFg = Color(light: 0x454C57, dark: 0xB4BBC7)
    static let select = Color(light: 0x1D4ED8, dark: 0x6B9BFF)
    static let holiday = Color(light: 0xB91C1C, dark: 0xF87171)
    static let fallbackCategory = Color(uiColor: UIColor(rgb: 0x1D4ED8))
}

/// 跟著系統字體大小縮放的固定字級
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
    func sFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
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
    var spacing: CGFloat = 4

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
