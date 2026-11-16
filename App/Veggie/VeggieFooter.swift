import SwiftUI
import UIKit

/// 設定頁最下面：logo、版本號、Made by DOMYWEB、網站和社群連結。長按版本號複製版本資訊，回報問題時用。
struct VeggieFooter: View {
    /// 請設定頁在上方跳一下提示
    let show: (String) -> Void

    /// logo 的邊長與圓角、社群圖示的邊長
    private let logoSide: CGFloat = 64
    private let logoRadius: CGFloat = 14
    private let brandIconSide: CGFloat = 26

    var body: some View {
        VStack(spacing: DT.Space.s3) {
            Image("AppLogo")
                .resizable()
                .frame(width: logoSide, height: logoSide)
                .clipShape(RoundedRectangle(cornerRadius: logoRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: DT.Space.s1) {
                Text(VeggieConfig.current.versionLine)
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.sub)
                Text(VeggieText.madeBy)
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
            .contentShape(Rectangle())
            .onLongPressGesture {
                UIPasteboard.general.string = Feedback.diagnostics
                show(VeggieText.diagnosticsCopied)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("長按複製版本資訊")
            HStack(spacing: DT.Space.s4) {
                ForEach(VeggieConfig.current.links) { link in
                    if let url = link.url {
                        Link(destination: url) {
                            linkIcon(link.kind)
                                .foregroundStyle(Theme.sub)
                                .frame(width: DT.Size.touch, height: DT.Size.touch)
                                .background(Circle().fill(Theme.muted))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(link.label)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Space.s6)
    }

    @ViewBuilder
    private func linkIcon(_ kind: VeggieLink.Kind) -> some View {
        switch kind {
        case .website:
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .regular))
        case .facebook:
            brandIcon("Facebook")
        case .instagram:
            brandIcon("Instagram")
        }
    }

    private func brandIcon(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: brandIconSide, height: brandIconSide)
    }
}
