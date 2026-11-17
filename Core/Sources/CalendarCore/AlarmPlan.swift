import Foundation

/// 鬧鐘鈴聲。`fileName` 是 nil 的用系統的鬧鐘聲，其他是包在 app 裡的音檔。
public struct AlarmSound: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let fileName: String?

    public static let defaultID = "system"

    public static let all: [AlarmSound] = [
        AlarmSound(id: "system", name: "系統鬧鐘聲", fileName: nil),
        AlarmSound(id: "chime", name: "風鈴", fileName: "alarm-chime.wav"),
        AlarmSound(id: "marimba", name: "木琴", fileName: "alarm-marimba.wav"),
        AlarmSound(id: "beep", name: "嗶嗶", fileName: "alarm-beep.wav")
    ]

    /// 不認得的值當成系統鬧鐘聲
    public static func find(_ id: String) -> AlarmSound {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 一筆行程上的提醒，交給 `AlarmPlan` 算什麼時候響
public struct AlarmSource: Hashable, Sendable {
    /// 這一次發生的識別：事件識別碼加上這一次的開始時間（重複行程每一次都不同）
    public var occurrenceID: String
    public var title: String
    public var start: Date
    /// 開始前幾秒響（負數是開始前，例如 -1800 是 30 分鐘前）
    public var relativeOffsets: [TimeInterval]
    /// 指定某個時間點響的提醒
    public var absoluteDates: [Date]

    public init(occurrenceID: String, title: String, start: Date,
                relativeOffsets: [TimeInterval] = [], absoluteDates: [Date] = []) {
        self.occurrenceID = occurrenceID
        self.title = title
        self.start = start
        self.relativeOffsets = relativeOffsets
        self.absoluteDates = absoluteDates
    }
}

/// 要排的一個鬧鐘
public struct PlannedAlarm: Hashable, Sendable {
    /// 同一筆行程、同一個響的時間，key 就一樣。用來比對上次排過哪些。
    public var key: String
    public var title: String
    public var fireDate: Date
}

/// 把行事曆上的提醒換成鬧鐘：只排接下來一段時間內的、最多幾個，跟上次排的比對出要新增、要取消的。
public enum AlarmPlan {
    /// 往後看幾天
    public static let horizonDays = 30
    /// 最多同時排幾個，免得一次排太多
    public static let limit = 64

    public static func planned(_ sources: [AlarmSource], now: Date,
                               horizon: TimeInterval = TimeInterval(horizonDays * 86_400),
                               limit: Int = AlarmPlan.limit) -> [PlannedAlarm] {
        var seen = Set<String>()
        var result: [PlannedAlarm] = []
        for source in sources {
            let fires = source.relativeOffsets.map { source.start.addingTimeInterval($0) } + source.absoluteDates
            for fire in fires where fire > now && fire <= now.addingTimeInterval(horizon) {
                let key = "\(source.occurrenceID)|\(Int(fire.timeIntervalSince1970))"
                guard seen.insert(key).inserted else { continue }
                result.append(PlannedAlarm(key: key, title: source.title, fireDate: fire))
            }
        }
        result.sort { $0.fireDate == $1.fireDate ? $0.key < $1.key : $0.fireDate < $1.fireDate }
        return Array(result.prefix(limit))
    }

    /// 上次排好的（key → 鬧鐘編號）跟這次要的比：哪些要取消、哪些要新排
    public static func diff(scheduled: [String: UUID], wanted: [PlannedAlarm]) -> (cancel: [String], add: [PlannedAlarm]) {
        let wantedKeys = Set(wanted.map(\.key))
        let cancel = scheduled.keys.filter { !wantedKeys.contains($0) }.sorted()
        let add = wanted.filter { scheduled[$0.key] == nil }
        return (cancel, add)
    }

    /// 鬧鐘上顯示的字：「30 分鐘後：牙醫」；準時響的就只寫「牙醫」
    public static func alertTitle(_ alarm: PlannedAlarm, start: Date) -> String {
        let minutes = Int((start.timeIntervalSince(alarm.fireDate) / 60).rounded())
        if minutes <= 0 { return alarm.title }
        if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60)) 天後：\(alarm.title)" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小時後：\(alarm.title)" }
        return "\(minutes) 分鐘後：\(alarm.title)"
    }
}
