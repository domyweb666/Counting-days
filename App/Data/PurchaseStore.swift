import Foundation
import Observation
import StoreKit

/// 內購：一個非消耗性商品「蒜日子完整版」。
/// 「買了沒」只放在記憶體，每次都從 App Store 驗證過的交易重新算，不存進任何檔案。
/// 驗不出來、查詢失敗、還在載入，一律是沒買。
@MainActor
@Observable
final class PurchaseStore {
    /// App Store Connect 上的商品編號要跟這個一模一樣
    static let productID = "com.domyweb.countingdays.full"

    private(set) var isUnlocked = false
    private(set) var product: Product?
    private(set) var isBusy = false
    /// 正在抓商品資料。抓不到時畫面上有「再試一次」，抓的途中先不給按。
    private(set) var isLoadingProduct = false
    private(set) var message: String?
    /// 這則訊息是不是在講出了問題。「沒買過」「等核准」只是告知，畫面上不用紅字。
    private(set) var messageIsProblem = false

    private static let chargedHint = "如果已經被扣款，按下面的「恢復購買」就會解鎖。"
    private static let productMissing = "現在抓不到商品資料，可能是網路不通。按「再試一次」重新讀取。"

    private func say(_ text: String?, problem: Bool) {
        message = text
        messageIsProblem = text != nil && problem
    }

    /// 按鈕上顯示的價格。只用 App Store 回傳的字，程式裡不寫數字。
    var priceText: String? { product?.displayPrice }

    @ObservationIgnored private let onChange: @MainActor (Bool) -> Void
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        // 在別台裝置購買、家長核准、退款，都會從這裡通知
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    /// 重新算一次有沒有買
    func refresh() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            // 只認 App Store 驗證過的交易，驗不過的當作沒有
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                unlocked = true
            }
        }
        if unlocked != isUnlocked { isUnlocked = unlocked }
        onChange(unlocked)
    }

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let found = try await Product.products(for: [Self.productID])
            guard let match = found.first(where: { $0.id == Self.productID }) else {
                say(Self.productMissing, problem: true)
                return
            }
            product = match
            say(nil, problem: false)
        } catch {
            say("商品資料讀取失敗：\(error.localizedDescription)。按「再試一次」重新讀取。", problem: true)
        }
    }

    /// 回傳有沒有買成功
    func purchase() async -> Bool {
        guard !isBusy else { return false }
        guard let product else {
            say(Self.productMissing, problem: true)
            return false
        }
        isBusy = true
        defer { isBusy = false }
        say(nil, problem: false)
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    say("沒有完成購買：這筆交易沒有通過 App Store 驗證，沒有解鎖。" + Self.chargedHint, problem: true)
                    return false
                }
                await transaction.finish()
                await refresh()
                return isUnlocked
            case .userCancelled:
                return false
            case .pending:
                say("這筆購買還在等核准，核准後會自動解鎖。", problem: false)
                return false
            @unknown default:
                say("沒有完成購買。" + Self.chargedHint, problem: true)
                return false
            }
        } catch {
            say("沒有完成購買：\(error.localizedDescription)。" + Self.chargedHint, problem: true)
            return false
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        say(nil, problem: false)
        do {
            try await AppStore.sync()
        } catch {
            say("恢復購買沒有成功：\(error.localizedDescription)。確認網路後再按一次。", problem: true)
            return
        }
        await refresh()
        if !isUnlocked {
            say("這個 Apple 帳號沒有買過完整版。", problem: false)
        }
    }
}
