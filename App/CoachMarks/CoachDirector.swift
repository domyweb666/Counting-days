import SwiftUI
import CalendarCore

/// 引導的場務：決定什麼時候開始，並在每一步把月曆擺成那一步該有的樣子。
/// 引導期間月曆吃的是範例行程和範例設定，都不會寫進手機；結束時還原。
struct CoachDirector: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(CoachController.self) private var coach

    /// 拿到權限、或使用者按了「重看教學」時會變，跟著重新判斷要不要開始
    private var startKey: String {
        "\(app.store.status == .fullAccess)-\(coach.startRequests)"
    }

    func body(content: Content) -> some View {
        content
            .task(id: startKey) {
                await startIfNeeded()
            }
            .onChange(of: coach.stateKey) {
                apply()
            }
            .onChange(of: app.vm.selected) { _, selected in
                // 「換你點點看」那一步：使用者真的點了今天，才前進
                guard let step = coach.current, step.kind == .tap, selected == app.vm.today else { return }
                coach.skipStep()
            }
    }

    /// 第一次進月曆、或從設定要求重看時，開始新手引導
    private func startIfNeeded() async {
        guard app.store.status == .fullAccess, coach.shouldStart else { return }
        try? await Task.sleep(for: .seconds(CoachStyle.startDelay))
        guard !Task.isCancelled, app.store.status == .fullAccess else { return }
        // 收起鍵盤
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        coach.begin()
    }

    private func apply() {
        let vm = app.vm
        guard let step = coach.current else {
            end()
            return
        }
        if vm.demoEvents == nil {
            vm.demoEvents = CoachDemo.events(today: vm.today, calendar: vm.calendar)
            // 今天那一週捲到最上面，時間軸也從今天排起
            vm.jump(to: vm.today, select: false)
        }

        var view = ViewKind.month
        var mode = DisplayMode.flex
        switch step.kind {
        case .demoViews:
            if CoachTour.views.indices.contains(coach.demoIndex) { view = CoachTour.views[coach.demoIndex] }
        case .demoStyles:
            if CoachTour.styles.indices.contains(coach.demoIndex) { mode = CoachTour.styles[coach.demoIndex] }
        case .plain, .tap, .fakeMenu:
            break
        }
        app.settings.beginPreview { s in
            s.categories = AppSettings.defaultCategories
            s.calendarCategory = CoachDemo.calendarCategory
            s.keywordRules = []
            s.pinned = []
            s.shortNames = [:]
            s.countdowns = []
            s.view = view
            s.mode = mode
        }

        let wanted: Date? = step.showsDayPanel ? vm.today : nil
        if vm.selected != wanted { vm.selected = wanted }
        vm.rebuild()
    }

    /// 引導結束：範例行程拿掉，設定還原成使用者原本的
    private func end() {
        let vm = app.vm
        guard vm.demoEvents != nil || app.settings.isPreviewing else { return }
        vm.demoEvents = nil
        vm.selected = nil
        app.settings.endPreview()
        vm.rebuild()
    }
}
