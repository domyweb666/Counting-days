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
    var message: String?

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
        guard product == nil else { return }
        do {
            let found = try await Product.products(for: [Self.productID])
            guard let match = found.first(where: { $0.id == Self.productID }) else {
                message = "現在抓不到商品資料，請稍後再試。"
                return
            }
            product = match
            message = nil
        } catch {
            message = "商品資料讀取失敗：\(error.localizedDescription)"
        }
    }

    /// 回傳有沒有買成功
    func purchase() async -> Bool {
        guard !isBusy else { return false }
        guard let product else {
            message = "現在抓不到商品資料，請稍後再試。"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        message = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "這筆購買沒有通過 App Store 驗證，沒有解鎖。"
                    return false
                }
                await transaction.finish()
                await refresh()
                return isUnlocked
            case .userCancelled:
                return false
            case .pending:
                message = "這筆購買還在等核准，核准後會自動解鎖。"
                return false
            @unknown default:
                message = "購買沒有完成。"
                return false
            }
        } catch {
            message = "購買失敗：\(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        message = nil
        do {
            try await AppStore.sync()
        } catch {
            message = "恢復購買失敗：\(error.localizedDescription)"
            return
        }
        await refresh()
        if !isUnlocked {
            message = "這個 Apple 帳號沒有買過完整版。"
        }
    }
}
