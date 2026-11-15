import Foundation
import Observation

/// 引導的狀態：有沒有在進行、目前第幾步
@MainActor
@Observable
final class CoachController {
    let steps: [CoachStep]
    private(set) var isActive = false
    private(set) var index = 0
    /// 每要求開始一次加一。根畫面看到這個數字變了，就做準備再開始。
    private(set) var startRequests = 0
    /// 使用者在設定按了「重看教學」，還沒真的開始
    private(set) var pendingStart = false

    @ObservationIgnored private let defaults: UserDefaults
    /// 步驟大改時把 v1 改成 v2，看過舊版的人會再看一次
    private static let completedKey = "coachTour.v1.completed"

    init(steps: [CoachStep] = CoachTour.steps, defaults: UserDefaults = .standard) {
        self.steps = steps
        self.defaults = defaults
    }

    var current: CoachStep? {
        guard isActive, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

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
        isActive = true
    }

    func next() {
        guard isActive else { return }
        if index + 1 < steps.count {
            index += 1
        } else {
            finish()
        }
    }

    func skip() {
        guard isActive else { return }
        finish()
    }

    /// 看完或跳過才算看過。中途關掉 app 不會走到這裡，下次會從第一步重來。
    private func finish() {
        isActive = false
        defaults.set(true, forKey: Self.completedKey)
    }
}
