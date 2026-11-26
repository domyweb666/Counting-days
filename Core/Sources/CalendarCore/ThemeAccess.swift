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

/// 完整版裡主題以外的四樣：倒數日的數量、月曆樣式、類別自訂顏色、中大尺寸與鎖定畫面的小工具。
/// 「能不能用」只在這個檔決定，畫面和 store 只問結果。驗不到購買時 `isUnlocked` 是 false，一律照沒買的算。
public enum FullVersionAccess {
    /// 沒買的人最多放幾個倒數日
    public static let freeCountdownLimit = 3

    /// 還能不能再加一個倒數日。移出不受限制，不用問這裡。
    public static func canAddCountdown(currentCount: Int, isUnlocked: Bool) -> Bool {
        isUnlocked || currentCount < freeCountdownLimit
    }

    /// 月曆上實際顯示哪幾個倒數日。
    /// 退款或還沒驗到購買時只顯示最早加入的幾個；其餘留在設定裡不刪，驗到之後自己回來。
    public static func visibleCountdowns(_ ids: [String], isUnlocked: Bool) -> [String] {
        isUnlocked ? ids : Array(ids.prefix(freeCountdownLimit))
    }

    /// 不用買就能用的月曆樣式
    public static let freeModes: Set<DisplayMode> = [.flex, .list]
    /// 選的樣式不能用時退回這一種
    public static let fallbackMode: DisplayMode = .flex

    public static func isFree(_ mode: DisplayMode) -> Bool {
        freeModes.contains(mode)
    }

    /// 這種樣式能不能正式套用（存進設定）
    public static func canApply(_ mode: DisplayMode, isUnlocked: Bool) -> Bool {
        isFree(mode) || isUnlocked
    }

    /// 月曆實際要用哪一種樣式。規則跟主題一樣：試看中用試看那種；選了付費樣式但沒買就退回預設，設定裡的選擇留著。
    public static func effectiveMode(selected: DisplayMode, previewing: DisplayMode?, isUnlocked: Bool) -> DisplayMode {
        if let previewing { return previewing }
        return canApply(selected, isUnlocked: isUnlocked) ? selected : fallbackMode
    }

    /// 類別能不能選任意顏色。沒買的人只能從預設那幾色挑。
    public static func canUseCustomCategoryColor(isUnlocked: Bool) -> Bool {
        isUnlocked
    }

    /// 選色時先列出來的預設顏色（就是四個預設類別的顏色，會跟著主題換）
    public static var presetCategoryHexes: [String] {
        AppSettings.defaultCategories.map(\.colorHex)
    }

    /// 不用買就能放的小工具：小尺寸「今天」與色塊小月曆。其他的要完整版（2026-11-26 使用者核准的切法）。
    public static let freeWidgets: Set<WidgetStyle> = [.today, .smallMonth, .lockToday]

    /// 這種小工具能不能畫內容。不能的話小工具只畫一句說明。小工具驗不到購買時 `isUnlocked` 是 false。
    public static func canShowWidget(_ style: WidgetStyle, isUnlocked: Bool) -> Bool {
        freeWidgets.contains(style) || isUnlocked
    }

    /// 存下來的設定有沒有用到付費的東西。有的話，開 app 時要等購買驗完再畫第一個畫面，才不會先閃一下沒買的樣子。
    public static func usesPaidContent(_ settings: AppSettings) -> Bool {
        !ThemeAccess.isFree(settings.themeID)
            || !isFree(settings.mode)
            || settings.countdowns.count > freeCountdownLimit
    }
}
