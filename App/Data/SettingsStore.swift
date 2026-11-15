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
    @ObservationIgnored private var isUnlocked = false

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

    // MARK: 新手引導的範例設定

    /// 引導期間先把使用者真正的設定收在這裡，結束時放回去
    @ObservationIgnored private var savedBeforePreview: AppSettings?

    var isPreviewing: Bool { savedBeforePreview != nil }

    /// 暫時改成範例設定。只改畫面上看到的，不寫進手機。
    func beginPreview(_ change: (inout AppSettings) -> Void) {
        if savedBeforePreview == nil { savedBeforePreview = value }
        var next = value
        change(&next)
        if next != value { value = next }
        applyTheme()
    }

    /// 還原成引導開始前的設定
    func endPreview() {
        guard let saved = savedBeforePreview else { return }
        savedBeforePreview = nil
        value = saved
        applyTheme()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        value = next
        applyTheme()
        // 引導期間的改動都是範例，不存檔
        guard savedBeforePreview == nil else { return }
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

    func toggleCountdown(_ seriesID: String) {
        update {
            if let i = $0.countdowns.firstIndex(of: seriesID) {
                $0.countdowns.remove(at: i)
            } else {
                $0.countdowns.append(seriesID)
            }
        }
    }

    func removeCategory(_ id: String) {
        update { s in
            guard s.categories.count > 1 else { return }
            s.categories.removeAll { $0.id == id }
            s.calendarCategory = s.calendarCategory.filter { $0.value != id }
            s.keywordRules.removeAll { $0.categoryID == id }
        }
    }
}
