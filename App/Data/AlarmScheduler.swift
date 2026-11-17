import EventKit
import Foundation
import Observation
import SwiftUI
import CalendarCore
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif

/// 「提醒用鬧鐘響」：把行事曆上接下來 30 天的提醒，各排一個 iPhone 鬧鐘（iOS 26 的 AlarmKit）。
///
/// 行事曆本身的提醒照舊留著，換手機、Google 日曆一樣會提醒；鬧鐘只在這支手機上多響一次。
/// 每次打開 app、行事曆有變動、開關或鈴聲換了，就重新比對一次：多的取消、少的補排。
/// 排過哪些記在手機上（行程那一次 + 響的時間 → 鬧鐘編號），不然下次分不出哪些是我們排的。
@MainActor
@Observable
final class AlarmScheduler {
    enum Permission {
        /// iOS 26 以前沒有鬧鐘可以用
        case unsupported
        case notDetermined
        case authorized
        case denied
    }

    private(set) var permission: Permission = .unsupported
    var lastError: String?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let scheduledKey = "alarm.scheduled"
    @ObservationIgnored private let soundKey = "alarm.scheduledSound"
    @ObservationIgnored private var isSyncing = false

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    init() {
        refreshPermission()
    }

    func refreshPermission() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: permission = .authorized
            case .denied: permission = .denied
            default: permission = .notDetermined
            }
        }
        #endif
    }

    /// 跳系統的權限視窗。答應了回傳 true。
    func requestPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
            } catch {
                lastError = "要求鬧鐘權限時出錯：\(error.localizedDescription)"
            }
            refreshPermission()
        }
        #endif
        return permission == .authorized
    }

    // MARK: 比對與排程

    /// 照目前的設定把鬧鐘排好。沒開、沒權限就把排過的全部取消。
    func sync(store: EventStore, calendars: [EKCalendar], settings: AppSettings) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        refreshPermission()

        var scheduled = loadScheduled()
        let wanted: [PlannedAlarm]
        if settings.alarmEnabled, permission == .authorized, store.hasAccess, !calendars.isEmpty {
            wanted = AlarmPlan.planned(sources(store: store, calendars: calendars), now: Date())
        } else {
            wanted = []
        }
        // 換了鈴聲：已經排好的要全部重排才會用新的聲音
        if defaults.string(forKey: soundKey) != settings.alarmSoundID {
            for id in scheduled.values { try? AlarmManager.shared.cancel(id: id) }
            scheduled = [:]
        }
        // 手機上已經沒有的鬧鐘（響過、被使用者關掉）不用再記
        let alive = Set((try? AlarmManager.shared.alarms.map(\.id)) ?? [])
        scheduled = scheduled.filter { alive.contains($0.value) }

        let (cancel, add) = AlarmPlan.diff(scheduled: scheduled, wanted: wanted)
        for key in cancel {
            if let id = scheduled[key] { try? AlarmManager.shared.cancel(id: id) }
            scheduled[key] = nil
        }
        let sound = AlarmSound.find(settings.alarmSoundID)
        let starts = Dictionary(wanted.map { ($0.key, startDates[$0.key] ?? $0.fireDate) }, uniquingKeysWith: { a, _ in a })
        for alarm in add {
            do {
                let id = try await schedule(alarm, start: starts[alarm.key] ?? alarm.fireDate, sound: sound)
                scheduled[alarm.key] = id
            } catch {
                lastError = "排鬧鐘時出錯：\(error.localizedDescription)"
                break
            }
        }
        saveScheduled(scheduled)
        defaults.set(settings.alarmSoundID, forKey: soundKey)
        #endif
    }

    /// 每個要排的鬧鐘對應的行程開始時間，鬧鐘上寫「30 分鐘後：牙醫」要用
    @ObservationIgnored private var startDates: [String: Date] = [:]

    private func sources(store: EventStore, calendars: [EKCalendar]) -> [AlarmSource] {
        let now = Date()
        // 往前多看一天：明天的全天行程，提醒可能在今天
        let from = now.addingTimeInterval(-86_400)
        let to = now.addingTimeInterval(TimeInterval((AlarmPlan.horizonDays + 2) * 86_400))
        let predicate = store.ek.predicateForEvents(withStart: from, end: to, calendars: calendars)
        var result: [AlarmSource] = []
        var starts: [String: Date] = [:]
        for event in store.ek.events(matching: predicate) {
            guard let alarms = event.alarms, !alarms.isEmpty, let start = event.startDate else { continue }
            let occurrence = "\(event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))"
            let source = AlarmSource(
                occurrenceID: occurrence,
                title: event.title ?? "",
                start: start,
                relativeOffsets: alarms.filter { $0.absoluteDate == nil }.map(\.relativeOffset),
                absoluteDates: alarms.compactMap(\.absoluteDate)
            )
            result.append(source)
            for fire in source.relativeOffsets.map({ start.addingTimeInterval($0) }) + source.absoluteDates {
                starts["\(occurrence)|\(Int(fire.timeIntervalSince1970))"] = start
            }
        }
        startDates = starts
        return result
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func schedule(_ alarm: PlannedAlarm, start: Date, sound: AlarmSound) async throws -> UUID {
        let id = UUID()
        let title = AlarmPlan.alertTitle(alarm, start: start)
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "關掉", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes<EventAlarmData>(
            presentation: AlarmPresentation(alert: alert),
            metadata: EventAlarmData(),
            tintColor: Theme.accent
        )
        let alertSound: AlertConfiguration.AlertSound = sound.fileName.map { .named($0) } ?? .default
        let configuration = AlarmManager.AlarmConfiguration<EventAlarmData>(
            schedule: .fixed(alarm.fireDate),
            attributes: attributes,
            sound: alertSound
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        return id
    }
    #endif

    // MARK: 記在手機上的對照表

    private func loadScheduled() -> [String: UUID] {
        let raw = defaults.dictionary(forKey: scheduledKey) as? [String: String] ?? [:]
        return raw.compactMapValues(UUID.init(uuidString:))
    }

    private func saveScheduled(_ map: [String: UUID]) {
        defaults.set(map.mapValues(\.uuidString), forKey: scheduledKey)
    }
}

#if canImport(AlarmKit)
/// 鬧鐘上不用帶額外資料，但 AlarmKit 要一個型別
@available(iOS 26.0, *)
struct EventAlarmData: AlarmMetadata {}
#endif
