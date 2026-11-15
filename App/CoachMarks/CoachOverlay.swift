import SwiftUI

/// 引導的整層畫面：黑幕與洞在下，跳過按鈕與說明卡在上
struct CoachOverlay: View {
    @Environment(CoachController.self) private var coach
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let anchors: [String: Anchor<CGRect>]

    /// 說明卡上緣在螢幕上的位置。一張張看的時候，洞的下緣要停在它上面。
    @State private var cardTop: CGFloat = 0

    var body: some View {
        ZStack {
            if let step = coach.current {
                // 黑幕蓋滿整個螢幕（含動態島與底部）
                GeometryReader { proxy in
                    CoachSpotlight(
                        step: step,
                        target: anchors[step.targetID].map { proxy[$0] },
                        clipBottom: step.isDemo && cardTop > 0 ? cardTop - CoachStyle.demoGap : nil,
                        dim: scheme == .dark ? CoachStyle.dimDark : CoachStyle.dimLight,
                        reduceMotion: reduceMotion,
                        onMissing: { coach.skipStep() }
                    )
                }
                .ignoresSafeArea()
                .transition(.opacity)

                // 跳過按鈕與說明卡留在安全區域裡
                GeometryReader { proxy in
                    let atTop = cardAtTop(step, target: anchors[step.targetID].map { proxy[$0] }, height: proxy.size.height)
                    VStack(spacing: 0) {
                        HStack {
                            Spacer(minLength: 0)
                            skipButton
                        }
                        .padding(.top, CoachStyle.skipTop)
                        .padding(.trailing, CoachStyle.skipTrailing)
                        if !atTop { Spacer(minLength: DT.Space.s3) }
                        CoachCard(
                            step: step,
                            index: coach.index,
                            total: coach.steps.count,
                            demoItems: coach.demoItems,
                            demoIndex: coach.demoIndex,
                            maxHeight: proxy.size.height * CoachStyle.cardMaxHeightRatio,
                            reduceMotion: reduceMotion,
                            onNext: { coach.next() },
                            onSelectDemo: { coach.selectDemo($0) },
                            onSkipStep: { coach.skipStep() }
                        )
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.frame(in: .global).minY
                        } action: { top in
                            cardTop = top
                        }
                        .padding(.horizontal, CoachStyle.cardMargin)
                        .padding(.top, atTop ? DT.Space.s2 : 0)
                        .padding(.bottom, DT.Space.s3)
                        if atTop { Spacer(minLength: 0) }
                    }
                }
                .accessibilityAddTraits(.isModal)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: CoachStyle.fade), value: coach.isActive)
        .sensoryFeedback(.selection, trigger: coach.stateKey)
    }

    /// 卡片預設在下面。洞會碰到卡片、或那一步要在洞下面畫選單時，改放上面。
    private func cardAtTop(_ step: CoachStep, target: CGRect?, height: CGFloat) -> Bool {
        if step.kind == .fakeMenu { return true }
        if step.isDemo { return false }
        guard let target else { return false }
        return target.maxY + step.holePadding > height - CoachStyle.cardEstimatedHeight
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

/// 黑幕、洞、光暈。整片攔截觸控；只有「換你點點看」那一步，洞裡面點得到。
private struct CoachSpotlight: View {
    let step: CoachStep
    /// 目標元件在螢幕上的位置；還沒出現時是 nil
    let target: CGRect?
    /// 洞的下緣最低到哪裡（一張張看的時候，停在說明卡上面）
    let clipBottom: CGFloat?
    let dim: Double
    let reduceMotion: Bool
    let onMissing: () -> Void

    @State private var hole: CGRect = .zero
    @State private var hasTarget = false
    /// 減少動態效果時用：先把洞蓋掉，換好位置再露出來
    @State private var covered = false
    @State private var swapTask: Task<Void, Never>?
    @State private var menuShown = false

    private var wanted: CGRect? {
        guard var rect = target?.insetBy(dx: -(step.holePaddingX ?? step.holePadding), dy: -step.holePadding) else { return nil }
        if let clipBottom {
            rect.size.height = max(0, min(rect.size.height, clipBottom - rect.origin.y))
        }
        return rect
    }

    var body: some View {
        ZStack {
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: true)
                .fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: false)
                .fill(Color.black.opacity(dim))
                .opacity(covered ? 1 : 0)
                .allowsHitTesting(false)
            SpotlightShape(hole: hole, cornerRadius: step.holeCornerRadius, inverted: false)
                .stroke(Theme.accent, lineWidth: CoachStyle.glowWidth)
                .shadow(color: Theme.accent.opacity(CoachStyle.glowOpacity), radius: CoachStyle.glowRadius)
                .opacity(hasTarget && !covered ? 1 : 0)
                .allowsHitTesting(false)
            // 攔觸控的那一層。平常整片都攔；「換你點點看」那一步把洞留空，點得到下面的元件。
            Color.clear
                .contentShape(
                    SpotlightShape(hole: step.kind == .tap ? hole : .zero,
                                   cornerRadius: step.holeCornerRadius, inverted: true),
                    eoFill: true
                )
                .onTapGesture {}
            if step.kind == .fakeMenu, hasTarget {
                CoachFakeMenu()
                    .frame(width: CoachStyle.fakeMenuWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: hole.minX + CoachStyle.fakeMenuInset, y: hole.maxY + CoachStyle.fakeMenuGap)
                    .opacity(menuShown ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
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
        .task(id: step.id) {
            // 長按選單的示意晚一點才出現，先讓人看到被照亮的是哪一列
            menuShown = false
            guard step.kind == .fakeMenu else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(CoachStyle.fakeMenuDelay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeIn(duration: CoachStyle.cardFadeIn)) { menuShown = true }
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

/// 長按選單的示意。iPhone 自己的長按選單沒辦法由程式打開，所以畫一個樣子接近的。
private struct CoachFakeMenu: View {
    private let items = ["置頂為當天主事件", "設定短名", "加入倒數日", "編輯"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                if index > 0 { Hairline() }
                Text(title)
                    .dFont(DT.TypeScale.callout)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, DT.Space.s3)
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
            }
        }
        .padding(.horizontal, DT.Space.s1)
        .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(Theme.card))
        .domyShadow(DT.Elevation.level2)
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
