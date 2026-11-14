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
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        value = next
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
