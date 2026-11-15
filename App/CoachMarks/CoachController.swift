import Foundation
import Observation

/// 引導的狀態：有沒有在進行、目前第幾步
@MainActor
@Observable
final class CoachController {
    let steps: [CoachStep]
    private(set) var isActive = false
    private(set) var index = 0
    /// 一張張看的步驟裡，目前看到第幾張
    private(set) var demoIndex = 0
    /// 每要求開始一次加一。根畫面看到這個數字變了，就做準備再開始。
    private(set) var startRequests = 0
    /// 使用者在設定按了「重看教學」，還沒真的開始
    private(set) var pendingStart = false

    @ObservationIgnored private let defaults: UserDefaults
    /// 步驟大改時把版本號加一，看過舊版的人會再看一次
    private static let completedKey = "coachTour.v2.completed"

    init(steps: [CoachStep] = CoachTour.steps, defaults: UserDefaults = .standard) {
        self.steps = steps
        self.defaults = defaults
    }

    var current: CoachStep? {
        guard isActive, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    /// 目前這一步要一張張看的東西；不是那種步驟就是空的
    var demoItems: [CoachDemoItem] {
        guard let current else { return [] }
        return CoachTour.demoItems(for: current.kind)
    }

    /// 引導的狀態一變這串字就變，畫面靠它知道要換範例月曆的樣子
    var stateKey: String { "\(isActive)-\(index)-\(demoIndex)" }

    var hasCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

    /// 沒看過，或使用者要求重看
    var shouldStart: Bool { pendingStart || !hasCompleted }

    /// 設定頁的「重看教學」
    func requestStart() {
        guard !isActive else { return }
        pendingStart = true
        startRequests += 1
    }

    func begin() {
        pendingStart = false
        guard !isActive, !steps.isEmpty else { return }
        index = 0
        demoIndex = 0
        isActive = true
    }

    /// 「知道了」或「下一個」：一張張看的步驟先看完每一張，再到下一步
    func next() {
        guard isActive else { return }
        if demoIndex + 1 < demoItems.count {
            demoIndex += 1
            return
        }
        skipStep()
    }

    /// 直接到下一步
    func skipStep() {
        guard isActive else { return }
        demoIndex = 0
        if index + 1 < steps.count {
            index += 1
        } else {
            finish()
        }
    }

    /// 一張張看的時候，直接點名稱跳到那一張
    func selectDemo(_ i: Int) {
        guard isActive, demoItems.indices.contains(i) else { return }
        demoIndex = i
    }

    func skip() {
        guard isActive else { return }
        finish()
    }

    /// 看完或跳過才算看過。中途關掉 app 不會走到這裡，下次會從第一步重來。
    private func finish() {
        isActive = false
        demoIndex = 0
        defaults.set(true, forKey: Self.completedKey)
    }
}
