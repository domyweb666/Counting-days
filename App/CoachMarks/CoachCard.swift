import SwiftUI

/// 說明卡：頭像、進度小點、標題、內文、「知道了」
struct CoachCard: View {
    let step: CoachStep
    let index: Int
    let total: Int
    /// 卡片高度上限。內文超過時改成可以捲動。
    let maxHeight: CGFloat
    let reduceMotion: Bool
    let onNext: () -> Void

    var body: some View {
        // 換步驟時裡面整個重來：打字進度歸零、淡入、VoiceOver 焦點移過來
        CoachCardContent(
            step: step,
            index: index,
            total: total,
            bodyMaxHeight: max(maxHeight - CoachStyle.cardChrome, CoachStyle.cardBodyMinHeight),
            reduceMotion: reduceMotion,
            onNext: onNext
        )
        .id(step.id)
        .padding(DT.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: CoachStyle.cardRadius).fill(Theme.card))
        .domyShadow(DT.Elevation.level2)
    }
}

private struct CoachCardContent: View {
    let step: CoachStep
    let index: Int
    let total: Int
    let bodyMaxHeight: CGFloat
    let reduceMotion: Bool
    let onNext: () -> Void

    /// 內文已經打出幾個字
    @State private var shown = 0
    @State private var appeared = false
    @AccessibilityFocusState private var focused: Bool

    private var characters: [Character] { Array(step.body) }
    private var isTyping: Bool { shown < characters.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.s3) {
            VStack(alignment: .leading, spacing: DT.Space.s3) {
                HStack(spacing: DT.Space.s3) {
                    Image("CoachAvatar")
                        .resizable()
                        .frame(width: CoachStyle.avatar, height: CoachStyle.avatar)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
                    dots
                    Spacer(minLength: 0)
                }
                Text(step.title)
                    .dFont(DT.TypeScale.headline)
                    .foregroundStyle(Theme.ink)
                ViewThatFits(in: .vertical) {
                    bodyText
                    ScrollView { bodyText }
                }
                .frame(maxHeight: bodyMaxHeight)
            }
            // VoiceOver 一次讀完，不跟著打字機一個字一個字唸
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(index + 1) 步，共 \(total) 步。\(step.title)。\(step.body)")
            .accessibilityFocused($focused)

            HStack {
                Spacer(minLength: 0)
                nextButton
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: CoachStyle.cardFadeIn)) { appeared = true }
        }
        .task {
            // 等卡片出現在畫面上再搬焦點，太早搬 VoiceOver 會沒反應
            try? await Task.sleep(for: .seconds(CoachStyle.fade))
            guard !Task.isCancelled else { return }
            focused = true
        }
        .task {
            await runTypewriter()
        }
    }

    /// 先用整段內文佔好位置（看不見），打出來的字疊在上面，卡片才不會邊打邊長高
    private var bodyText: some View {
        Text(step.body)
            .dFont(DT.TypeScale.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .topLeading) {
                Text(String(characters.prefix(shown)))
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
    }

    private var dots: some View {
        HStack(spacing: CoachStyle.dotGap) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Theme.tertiary)
                    .frame(width: i == index ? CoachStyle.dotCurrent : CoachStyle.dot, height: CoachStyle.dot)
            }
        }
    }

    private var nextButton: some View {
        Button {
            // 還在打字：先把全文顯示出來。已經顯示完：前進。
            if isTyping {
                shown = characters.count
            } else {
                onNext()
            }
        } label: {
            Text("知道了")
                .dFont(DT.TypeScale.callout)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, DT.Space.s5)
                .frame(height: CoachStyle.buttonHeight)
                .background(Capsule().fill(Theme.accent))
                .frame(minWidth: DT.Size.touch, minHeight: DT.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func runTypewriter() async {
        let all = characters
        if reduceMotion {
            shown = all.count
            return
        }
        while shown < all.count {
            let ch = all[shown]
            shown += 1
            let extra = CoachStyle.punctuation.contains(ch) ? CoachStyle.punctuationPause : 0
            try? await Task.sleep(for: .seconds(CoachStyle.typeInterval + extra))
            if Task.isCancelled { return }
        }
    }
}
