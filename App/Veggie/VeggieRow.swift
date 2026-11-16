import SwiftUI

/// 設定頁的一列：圖示＋名稱＋右側狀態或箭頭（› 是 app 內下一頁，↗ 是跳出 app）
struct VeggieRow: View {
    enum Accessory {
        case none
        /// app 內的下一頁
        case push
        /// 跳出 app（瀏覽器、App Store、寄信）
        case external
    }

    let icon: String
    let title: String
    var value: String?
    var accessory = Accessory.none

    var body: some View {
        HStack(spacing: DT.Space.s3) {
            VeggieRowIcon(systemName: icon)
            Text(title)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            }
            switch accessory {
            case .none:
                EmptyView()
            case .push:
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
            case .external:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.sub)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: DT.Size.row)
        .contentShape(Rectangle())
    }
}

/// 設定列最左邊的圖示。同一個功能在每個蔬菜 app 用同一個圖示。
struct VeggieRowIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Theme.accent)
            .frame(width: DT.Space.s6)
            .accessibilityHidden(true)
    }
}
