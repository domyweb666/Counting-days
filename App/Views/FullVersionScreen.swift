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
        "六款主題"
    ]

    private var purchase: PurchaseStore { app.purchase }

    var body: some View {
        if purchase.isUnlocked {
            Text("已解鎖完整版，六款主題都可以用。")
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
