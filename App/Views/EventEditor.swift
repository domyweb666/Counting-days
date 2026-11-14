import SwiftUI
import EventKit
import EventKitUI

/// 系統內建的事件編輯畫面。新增、修改、刪除都由它寫回系統行事曆，
/// 刪除前系統會自己再問一次。
struct EventEditor: UIViewControllerRepresentable {
    let store: EventStore
    /// nil 表示新增
    let event: EKEvent?
    let defaultDay: Date
    let calendar: Calendar
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store.ek
        if let event {
            vc.event = event
        } else {
            let new = EKEvent(eventStore: store.ek)
            let start = defaultStart()
            new.startDate = start
            new.endDate = start.addingTimeInterval(3600)
            new.calendar = store.ek.defaultCalendarForNewEvents
            vc.event = new
        }
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    /// 新增時日期帶入被選的那天：今天用下一個整點，其他天用早上 9 點
    private func defaultStart() -> Date {
        let day = calendar.startOfDay(for: defaultDay)
        let now = Date()
        if calendar.isDate(day, inSameDayAs: now) {
            let hour = calendar.component(.hour, from: now)
            if let next = calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: day) {
                return next
            }
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
