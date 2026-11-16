import SwiftUI

/// 蔬菜家族的其他 app：內建清單，點了開 App Store（或網頁）
struct VeggieFamilyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text(VeggieText.family)
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                SectionCard {
                    ForEach(Array(VeggieApp.others.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline() }
                        if let link = item.link {
                            Link(destination: link) {
                                HStack(spacing: DT.Space.s3) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .dFont(DT.TypeScale.headline)
                                            .foregroundStyle(Theme.ink)
                                        Text(item.tagline)
                                            .dFont(DT.TypeScale.subheadline)
                                            .foregroundStyle(Theme.sub)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("取得")
                                        .dFont(DT.TypeScale.callout)
                                        .foregroundStyle(Theme.strong)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.sub)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, DT.Space.s2)
                                .frame(minHeight: DT.Size.row)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("\(item.name)，\(item.tagline)，到 App Store 取得")
                        }
                    }
                }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
    }
}
