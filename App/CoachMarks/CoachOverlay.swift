import SwiftUI

/// 引導的整層畫面：黑幕與洞在下，跳過按鈕與說明卡在上
struct CoachOverlay: View {
    @Environment(CoachController.self) private var coach
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        ZStack {
            if let step = coach.current {
                // 黑幕蓋滿整個螢幕（含動態島與底部）
                GeometryReader { proxy in
                    CoachSpotlight(
                        step: step,
                        target: anchors[step.targetID].map { proxy[$0] },
                        dim: scheme == .dark ? CoachStyle.dimDark : CoachStyle.dimLight,
                        reduceMotion: reduceMotion,
                        onMissing: { coach.next() }
                    )
                }
                .ignoresSafeArea()
                .transition(.opacity)

                // 跳過按鈕與說明卡留在安全區域裡
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        HStack {
                            Spacer(minLength: 0)
                            skipButton
                        }
                        .padding(.top, CoachStyle.skipTop)
                        .padding(.trailing, CoachStyle.skipTrailing)
                        Spacer(minLength: DT.Space.s3)
                        CoachCard(
                            step: step,
                            index: coach.index,
                            total: coach.steps.count,
                            maxHeight: proxy.size.height * CoachStyle.cardMaxHeightRatio,
                            reduceMotion: reduceMotion,
                            onNext: { coach.next() }
                        )
                        .padding(.horizontal, CoachStyle.cardMargin)
                        .padding(.bottom, DT.Space.s3)
                    }
                }
                .accessibilityAddTraits(.isModal)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: CoachStyle.fade), value: coach.isActive)
        .sensoryFeedback(.selection, trigger: coach.index)
    }

    private var skipButton: some View {
        Button {
            coach.skip()
        } label: {
            HStack(spacing: DT.Space.s1) {
                Text("跳過教學").dFont(DT.TypeScale.footnote)
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, DT.Space.s3)
            .frame(height: DT.Size.pickerHeight)
            .background(Capsule().fill(Color.black.opacity(CoachStyle.skipFill)))
            .frame(minHeight: DT.Size.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("跳過教學")
    }
}

/// 黑幕、洞、光暈。整片攔截觸控，洞裡面也點不到。
private struct CoachSpotlight: View {
    let step: CoachStep
    /// 目標元件在螢幕上的位置；還沒出現時是 nil
    let target: CGRect?
    let dim: Double
    let reduceMotion: Bool
    let onMissing: () -> Void

    @State private var hole: CGRect = .zero
    @State private var hasTarget = false
    /// 減少動態效果時用：先把洞蓋掉，換好位置再露出來
    @State private var covered = false
    @State private var swapTask: Task<Void, Never>?

    private var wanted: CGRect? {
        target.map { $0.insetBy(dx: -step.holePadding, dy: -step.holePadding) }
    }

    var body: some View {
        ZStack {
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: true)
                .fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: false)
                .fill(Color.black.opacity(dim))
                .opacity(covered ? 1 : 0)
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: false)
                .stroke(Theme.accent, lineWidth: CoachStyle.glowWidth)
                .shadow(color: Theme.accent.opacity(CoachStyle.glowOpacity), radius: CoachStyle.glowRadius)
                .opacity(hasTarget && !covered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
        .onAppear {
            // 第一次出現跟著整層淡入，洞直接就位
            hasTarget = wanted != nil
            hole = wanted ?? .zero
        }
        .onChange(of: wanted) { _, next in
            move(to: next)
        }
        .task(id: step.id) {
            // 目標一直沒出現（例如那個元件這時候不在畫面上）就跳下一步，不卡住
            try? await Task.sleep(for: .seconds(CoachStyle.missingTargetWait))
            guard !Task.isCancelled, !hasTarget else { return }
            onMissing()
        }
        .onDisappear { swapTask?.cancel() }
    }

    private func move(to rect: CGRect?) {
        swapTask?.cancel()
        guard let rect else {
            // 等新目標回報位置的期間，洞原地收成 0
            hasTarget = false
            covered = false
            let closed = CGRect(x: hole.midX, y: hole.midY, width: 0, height: 0)
            if reduceMotion {
                hole = closed
            } else {
                withAnimation(CoachStyle.holeSpring) { hole = closed }
            }
            return
        }
        let wasEmpty = hole == .zero
        hasTarget = true
        if wasEmpty {
            hole = rect
            return
        }
        if reduceMotion {
            swapTask = Task {
                withAnimation(.easeOut(duration: CoachStyle.holeFadeOut)) { covered = true }
                try? await Task.sleep(for: .seconds(CoachStyle.holeFadeOut))
                guard !Task.isCancelled else { return }
                hole = rect
                withAnimation(.easeIn(duration: CoachStyle.holeFadeIn)) { covered = false }
            }
        } else {
            covered = false
            withAnimation(CoachStyle.holeSpring) { hole = rect }
        }
    }
}

/// inverted 為 true：整片畫面挖掉洞（配 even-odd 填色）。false：只有洞那一塊。
/// 洞的四個數值可以做動畫，換步驟時洞才會滑過去。
struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat
    var inverted: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(hole.origin.x, hole.origin.y),
                AnimatablePair(hole.size.width, hole.size.height)
            )
        }
        set {
            hole = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if inverted { path.addRect(rect) }
        // 彈簧動畫回彈時寬高可能短暫變成負的
        let w = hole.size.width
        let h = hole.size.height
        guard w > 0, h > 0 else { return path }
        let r = min(cornerRadius, w / 2, h / 2)
        path.addRoundedRect(
            in: CGRect(x: hole.origin.x, y: hole.origin.y, width: w, height: h),
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )
        return path
    }
}
