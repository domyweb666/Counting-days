import Foundation
import Observation
import SwiftUI
import CalendarCore

/// app 自己存的設定，放在這支手機的 UserDefaults。
@MainActor
@Observable
final class SettingsStore {
    private(set) var value: AppSettings
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "settings.v1"
    private static let brokenKey = "settings.v1.broken"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else {
            value = AppSettings()
            applyTheme()
            return
        }
        do {
            value = try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // 讀不回來就用預設值，但把壞掉的那份留著，不直接蓋掉
            defaults.set(data, forKey: Self.brokenKey)
            value = AppSettings()
            errorMessage = "設定檔讀取失敗，已改用預設值：\(error.localizedDescription)"
        }
        applyTheme()
    }

    /// 把設定裡選的主題套到畫面上。`value` 每次被換掉之後都要呼叫。
    private func applyTheme() {
        let id = ThemeAccess.effectiveThemeID(
            selected: value.themeID,
            previewing: previewThemeID,
            isUnlocked: isUnlocked
        )
        let next = ThemePalette.find(id)
        guard next.id != ThemeState.shared.palette.id else { return }
        ThemeState.shared.palette = next
    }

    // MARK: 主題的付費與試看

    /// 有沒有買完整版。由 `PurchaseStore` 告知，只放在記憶體，不存檔；還沒被告知之前是沒買。
    /// 月曆樣式、倒數日的畫面也要在這個值變的時候重畫，所以沒有排除在觀察之外。
    private var isUnlocked = false

    /// 正在試看的付費主題。只放在記憶體，不存檔。
    private(set) var previewThemeID: String?

    func setUnlocked(_ unlocked: Bool) {
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        applyTheme()
    }

    /// 正式選一款主題。沒買的付費款選不進設定，回傳 false。
    @discardableResult
    func selectTheme(_ id: String) -> Bool {
        guard ThemeAccess.canApply(id, isUnlocked: isUnlocked) else { return false }
        previewThemeID = nil
        update { $0.themeID = id }
        applyTheme()
        return true
    }

    /// 試看一款主題：只改畫面，不存檔。離開主題頁時要呼叫 `endThemePreview`。
    func previewTheme(_ id: String) {
        previewThemeID = id
        applyTheme()
    }

    func endThemePreview() {
        guard previewThemeID != nil else { return }
        previewThemeID = nil
        applyTheme()
    }

    // MARK: 完整版的另外三樣：月曆樣式、倒數日、類別自訂顏色
    // 能不能用都問 Core 的 `FullVersionAccess`，這裡只把「買了沒」帶進去。

    /// 正在試看的付費月曆樣式。只放在記憶體，不存檔。
    private(set) var previewingMode: DisplayMode?

    /// 月曆實際要畫成哪一種樣式
    var effectiveMode: DisplayMode {
        return FullVersionAccess.effectiveMode(selected: value.mode, previewing: previewingMode, isUnlocked: isUnlocked)
    }

    /// 正式選一種月曆樣式。沒買的付費樣式選不進設定，回傳 false。
    @discardableResult
    func selectMode(_ mode: DisplayMode) -> Bool {
        guard FullVersionAccess.canApply(mode, isUnlocked: isUnlocked) else { return false }
        previewingMode = nil
        update { $0.mode = mode }
        return true
    }

    /// 試看一種月曆樣式：只改畫面，不存檔。離開樣式頁時要呼叫 `endModePreview`。
    func previewMode(_ mode: DisplayMode) {
        previewingMode = mode
    }

    func endModePreview() {
        guard previewingMode != nil else { return }
        previewingMode = nil
    }

    /// 還能不能再加一個倒數日
    var canAddCountdown: Bool {
        FullVersionAccess.canAddCountdown(currentCount: value.countdowns.count, isUnlocked: isUnlocked)
    }

    /// 月曆上實際顯示的倒數日
    var visibleCountdowns: [String] {
        FullVersionAccess.visibleCountdowns(value.countdowns, isUnlocked: isUnlocked)
    }

    var canUseCustomCategoryColor: Bool {
        FullVersionAccess.canUseCustomCategoryColor(isUnlocked: isUnlocked)
    }

    /// 存下來的設定有沒有用到付費的東西（開 app 時決定要不要先等購買驗完）
    var usesPaidContent: Bool {
        FullVersionAccess.usesPaidContent(value)
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        value = next
        applyTheme()
        do {
            defaults.set(try JSONEncoder().encode(next), forKey: Self.key)
        } catch {
            errorMessage = "設定儲存失敗：\(error.localizedDescription)"
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.value[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    // MARK: 常用操作

    func togglePin(_ seriesID: String) {
        update {
            if $0.pinned.contains(seriesID) { $0.pinned.remove(seriesID) } else { $0.pinned.insert(seriesID) }
        }
    }

    func setShortName(_ name: String, for seriesID: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update {
            if clean.isEmpty { $0.shortNames.removeValue(forKey: seriesID) } else { $0.shortNames[seriesID] = clean }
        }
    }

    /// 加入或移出倒數日。沒買的人加到上限就加不進去，回傳 false；移出永遠可以。
    @discardableResult
    func toggleCountdown(_ seriesID: String) -> Bool {
        if !value.countdowns.contains(seriesID), !canAddCountdown { return false }
        update {
            if let i = $0.countdowns.firstIndex(of: seriesID) {
                $0.countdowns.remove(at: i)
            } else {
                $0.countdowns.append(seriesID)
            }
        }
        return true
    }

    func removeCategory(_ id: String) {
        update { s in
            guard s.categories.count > 1 else { return }
            s.categories.removeAll { $0.id == id }
            s.calendarCategory = s.calendarCategory.filter { $0.value != id }
            s.eventCategory = s.eventCategory.filter { $0.value != id }
            s.keywordRules.removeAll { $0.categoryID == id }
        }
    }
}
