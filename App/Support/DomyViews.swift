import SwiftUI

// 照 domy-design 的元件規格，用代號在蒜日子裡組的本地元件。
// 兩款以上的 SwiftUI App 都要用時，再搬進 domy-design。

/// 按下去的回饋：縮一點、變淡
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? DT.Motion.pressedOpacity : 1)
            .scaleEffect(configuration.isPressed ? DT.Motion.pressScale : 1)
            .animation(.easeOut(duration: DT.Motion.pressDuration), value: configuration.isPressed)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: DT.Size.hairline)
    }
}

/// 導覽列的白底圓鈕。primary 是整個畫面唯一的產品色實心鈕。
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var primary = false
    var size: CGFloat = DT.Size.iconButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(primary ? Theme.onAccent : Theme.accent)
                .frame(width: size, height: size)
                .background(Circle().fill(primary ? Theme.accent : Theme.card))
                .domyShadow(DT.Elevation.level1)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// 導覽列的白底文字膠囊（例：「今天」「完成」）
struct PillTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dFont(DT.TypeScale.callout)
                .foregroundStyle(Theme.strong)
                .padding(.horizontal, DT.Space.s4)
                .frame(height: DT.Size.iconButton)
                .background(Capsule().fill(Theme.card))
                .domyShadow(DT.Elevation.level1)
        }
        .buttonStyle(PressStyle())
    }
}

/// 一般按鈕。一個畫面最多一顆 primary。
struct WideButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var kind: Kind = .primary
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s2) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).dFont(DT.TypeScale.headline)
            }
            .foregroundStyle(kind == .primary ? Theme.onAccent : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: DT.Size.button)
            .background(Capsule().fill(kind == .primary ? Theme.accent : Theme.muted))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// 分組：標題＋一張白卡＋說明。卡裡的列之間請自己放 Hairline。
struct SectionCard<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            if let title {
                Text(title)
                    .dFont(DT.TypeScale.title3)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, DT.Space.s1)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, DT.Space.s4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
            if let footer {
                Text(footer)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                    .padding(.horizontal, DT.Space.s4)
            }
        }
    }
}

/// 設定列尾巴的產品色膠囊，點了開選單
struct PickerCapsule: View {
    let text: String

    var body: some View {
        HStack(spacing: DT.Space.s1) {
            Text(text).dFont(DT.TypeScale.callout).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.strong)
        .padding(.horizontal, DT.Space.s3)
        .frame(height: DT.Size.pickerHeight)
        .background(Capsule().fill(Theme.soft))
    }
}

/// 空狀態：說清楚這裡會出現什麼、下一步按哪裡
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DT.Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: DT.Size.emptyIcon, height: DT.Size.emptyIcon)
                .background(Circle().fill(Theme.soft))
            Text(title)
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .dFont(DT.TypeScale.subheadline)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, DT.Space.s8)
        .padding(.horizontal, DT.Space.s6)
        .frame(maxWidth: .infinity)
    }
}
