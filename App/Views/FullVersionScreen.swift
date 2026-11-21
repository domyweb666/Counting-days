import SwiftUI
import CalendarCore

/// 購買完整版的那一塊：買之前的說明、價格按鈕、恢復購買、訊息。
/// 主題頁最下面和「完整版」頁共用，字只寫在這裡（設計見 `.uiux/02-購買入口.md`）。
struct FullVersionOffer: View {
    @Environment(AppModel.self) private var app
    /// 按下購買鈕要做的事。主題頁要在買成功後套用正在試看的那一款，所以由外面給。
    let buy: () -> Void

    /// 完整版現在包含的東西。加了新的付費功能要回來補一行。
    static let features = [
        "六款主題",
        "週條、主事件兩種月曆樣式",
        "倒數日不限數量",
        "類別可以自訂顏色"
    ]

    private var purchase: PurchaseStore { app.purchase }

    var body: some View {
        Group {
            if purchase.isUnlocked {
                Text("已解鎖完整版：" + Self.features.joined(separator: "、") + "，都可以用。")
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                    .padding(.horizontal, DT.Space.s4)
            } else {
                VStack(alignment: .leading, spacing: DT.Space.s4) {
                    promise
                    actions
                }
            }
        }
        // 買成功、恢復成功時震一下。只掛在這一塊：掛在月曆上的話，買過的人每次開 app 驗到購買都會震。
        .sensoryFeedback(.success, trigger: purchase.isUnlocked) { _, now in now }
    }

    /// 買之前要看得到的承諾：有什麼、付一次、之後新增的也算
    private var promise: some View {
        VStack(alignment: .leading, spacing: DT.Space.s2) {
            Text("蒜日子完整版")
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("付一次就能一直用，沒有續訂。")
                .dFont(DT.TypeScale.subheadline)
                .foregroundStyle(Theme.ink)
            ForEach(Self.features, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: DT.Space.s2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(feature)
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
            Text("之後新增的付費功能也包含在內，不用再付一次。")
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.Space.s4)
    }

    private var actions: some View {
        VStack(spacing: DT.Space.s2) {
            if let message = purchase.message {
                Text(message)
                    .dFont(DT.TypeScale.footnote)
                    // 「沒買過」「等核准」只是告知，不用紅字嚇人
                    .foregroundStyle(purchase.messageIsProblem ? Theme.destructive : Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DT.Space.s4)
            }
            WideButton(title: purchase.priceText.map { "解鎖完整版　\($0)" } ?? "暫時無法購買", action: buy)
                .disabled(purchase.priceText == nil || purchase.isBusy)
                .opacity(purchase.priceText == nil || purchase.isBusy ? 0.5 : 1)
            if purchase.priceText == nil {
                textButton(purchase.isLoadingProduct ? "讀取中…" : "再試一次") {
                    Task { await purchase.loadProduct() }
                }
                .disabled(purchase.isLoadingProduct)
            }
            textButton("恢復購買") {
                Task { await purchase.restore() }
            }
            .disabled(purchase.isBusy)
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .dFont(DT.TypeScale.subheadline)
                .foregroundStyle(Theme.strong)
                .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// 為什麼來到「完整版」頁。主題和月曆樣式在自己那一頁就能買，不會開這一頁。
enum FullVersionReason: String {
    case countdown
    case categoryColor
    /// 從設定的「購買」那一區自己點進來的，沒有碰到哪個鎖
    case settings

    var text: String {
        switch self {
        case .settings:
            return "蒜日子可以免費一直用。下面這幾樣要完整版。"
        case .countdown:
            return "免費版可以放 \(FullVersionAccess.freeCountdownLimit) 個倒數日，再多要完整版。"
        case .categoryColor:
            return "免費版從預設的幾個顏色裡挑，自訂顏色要完整版。"
        }
    }
}

/// 獨立的「完整版」頁：從倒數日、類別顏色碰到鎖時打開。
/// 最上面一句說為什麼來到這裡，下面是跟主題頁共用的那一塊。
struct FullVersionSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let reason: FullVersionReason

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.s6) {
                HStack {
                    Spacer()
                    PillTextButton(title: "完成") { dismiss() }
                }
                Text("完整版")
                    .dFont(DT.TypeScale.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if !app.purchase.isUnlocked {
                    Text(reason.text)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                }
                FullVersionOffer {
                    Task { await app.purchase.purchase() }
                }
            }
            .padding(.horizontal, DT.Size.screenMargin)
            .padding(.top, DT.Space.s4)
            .padding(.bottom, DT.Space.s8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accent)
        .task { await app.purchase.loadProduct() }
    }
}
