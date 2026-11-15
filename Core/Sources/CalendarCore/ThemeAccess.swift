import Foundation

/// 主題的付費判斷。「畫面該用哪一款」只在這裡決定，其他地方不各自判斷。
public enum ThemeAccess {
    /// 不用買就能用的主題
    public static let freeThemeIDs: Set<String> = [AppSettings.defaultThemeID]

    public static func isFree(_ id: String) -> Bool {
        freeThemeIDs.contains(id)
    }

    /// 這款能不能正式套用（存進設定）
    public static func canApply(_ id: String, isUnlocked: Bool) -> Bool {
        isFree(id) || isUnlocked
    }

    /// 畫面實際要用哪一款。
    /// - 試看中：用試看的那款。試看只放在記憶體，離開主題頁就清掉。
    /// - 選的是付費款但沒有買（沒買過、退款、還沒驗到）：用預設款。設定裡的選擇留著，驗到之後自動回來。
    public static func effectiveThemeID(selected: String, previewing: String?, isUnlocked: Bool) -> String {
        if let previewing { return previewing }
        return canApply(selected, isUnlocked: isUnlocked) ? selected : AppSettings.defaultThemeID
    }
}
