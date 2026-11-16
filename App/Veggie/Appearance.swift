import SwiftUI
import UIKit

/// 外觀三選一：跟隨系統（預設）／淺色／深色。選完立刻生效，不用重開。
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    /// 手機裡存的那一個。沒存過或存的值不認得，就是跟隨系統。
    static var stored: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return VeggieText.appearanceSystem
        case .light: return VeggieText.appearanceLight
        case .dark: return VeggieText.appearanceDark
        }
    }

    private var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 套到整個 app。設在視窗上而不是某個畫面上：設定頁是彈出來的，
    /// 設在畫面上的話，彈出的那一層要關掉重開才會跟著變。
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
