import Foundation

/// 事件歸哪個類別：使用者替這一筆自己選的最優先，其次是關鍵字規則，再來看行事曆的預設類別，都沒有就歸「行程」。
/// 一本行事曆裡會有很多種行程，所以行事曆的類別只是沒選過時的預設。
public enum Classifier {
    public static func categoryID(for event: CalEvent, settings: AppSettings) -> String {
        let known = Set(settings.categories.map(\.id))
        if let own = settings.eventCategory[event.seriesID], known.contains(own) {
            return own
        }
        for rule in settings.keywordRules {
            let key = rule.keyword.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, known.contains(rule.categoryID) else { continue }
            if event.title.localizedCaseInsensitiveContains(key) { return rule.categoryID }
        }
        if let id = settings.calendarCategory[event.calendarID], known.contains(id) {
            return id
        }
        if known.contains(AppSettings.fallbackCategoryID) { return AppSettings.fallbackCategoryID }
        return settings.categories[0].id
    }
}

/// 全天行程沒有時區：6 月 1 日全天，在哪個時區看都是 6 月 1 日。
/// 系統給的起訖是手機時區的午夜，換一個時區排月曆時，要把鐘面上的時間原封不動搬過去，
/// 不然在東京看台北的全天行程，會從前一天晚上 11 點開始、跨到兩天。
public enum FloatingTime {
    public static func moved(_ date: Date, from: TimeZone, to: TimeZone) -> Date {
        let shift = from.secondsFromGMT(for: date) - to.secondsFromGMT(for: date)
        return date.addingTimeInterval(TimeInterval(shift))
    }
}

/// 行事曆的顯示順序：使用者排過的照他排的；沒排過的（例如剛加進手機的）接在後面，彼此維持原本的先後。
public enum CalendarOrder {
    /// 排第幾。不在使用者排的清單裡的，一律排最後。
    public static func rank(of calendarID: String, in order: [String]) -> Int {
        order.firstIndex(of: calendarID) ?? Int.max
    }

    public static func sorted(_ calendarIDs: [String], by order: [String]) -> [String] {
        calendarIDs.enumerated().sorted { a, b in
            let ra = rank(of: a.element, in: order)
            let rb = rank(of: b.element, in: order)
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }
        .map(\.element)
    }
}

/// 格子裡的字：6 個全形字以內完整顯示；超過就用短名，沒有短名取前 6 個字。
public enum CellText {
    /// 全形字算 2、半形字算 1，一格兩行共 12。
    public static let maxUnits = 12

    public static func units(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    }

    public static func label(title: String, shortName: String?) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if units(clean) <= maxUnits { return clean }
        if let s = shortName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return truncate(s)
        }
        return truncate(clean)
    }

    static func truncate(_ text: String) -> String {
        var used = 0
        var out = ""
        for ch in text {
            let u = ch.isASCII ? 1 : 2
            if used + u > maxUnits { break }
            used += u
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// 重疊的跨日事件，哪幾條寫字、哪幾條縮成細線。
/// 彈性週每條都寫字；主事件樣式只有第一條寫字，不然同一天還是會寫出好幾件。
public enum BandStyle {
    public static func isThin(lane: Int, mode: DisplayMode) -> Bool {
        mode == .head && lane >= 1
    }
}

/// 每天只有一件主事件。依序比較，分出高下就停：
/// 1. 使用者置頂的
/// 2. 有地點、有受邀者，或屬於優先類別（預設是生活）的
/// 3. 一次性事件優先於重複事件
/// 4. 當天開始時間最早的
/// 5. 開始時間也一樣，照使用者排的行事曆順序
public enum HeadPicker {
    public static func pick(_ events: [ClassifiedEvent], settings: AppSettings) -> ClassifiedEvent? {
        guard !events.isEmpty else { return nil }
        let priority = Set(settings.categories.filter(\.isPriority).map(\.id))

        func rank(_ e: ClassifiedEvent) -> [Int] {
            let weighty = e.event.hasLocation || e.event.hasAttendees || priority.contains(e.categoryID)
            return [
                e.isPinned ? 0 : 1,
                weighty ? 0 : 1,
                e.event.isRecurring ? 1 : 0
            ]
        }

        return events.min { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra.lexicographicallyPrecedes(rb) }
            if a.event.start != b.event.start { return a.event.start < b.event.start }
            let ca = CalendarOrder.rank(of: a.event.calendarID, in: settings.calendarOrder)
            let cb = CalendarOrder.rank(of: b.event.calendarID, in: settings.calendarOrder)
            if ca != cb { return ca < cb }
            return a.event.id < b.event.id
        }
    }
}

/// 左右滑放手的那一刻，算不算數（時間軸換頁、側邊欄收起共用）。
/// 距離與速度都以「要去的那個方向」為正。
public enum SwipeRules {
    /// 慢慢拉的話，拉過多遠算數（點）
    public static let commitDistance = 40.0
    /// 甩多快算數（點／秒）
    public static let flickVelocity = 300.0
    /// 往不能去的方向拉，最多只讓它動這麼遠（點）
    public static let resistLimit = 24.0
    /// 往不能去的方向拉，一開始跟手的比例
    private static let resistRatio = 0.5

    /// 甩得夠快就照甩的方向：往前甩一律算數，往回甩是反悔、一律不算。沒有甩才看拉了多遠。
    public static func commits(distance: Double, velocity: Double) -> Bool {
        guard distance > 0 else { return false }
        if velocity >= flickVelocity { return true }
        if velocity <= -flickVelocity { return false }
        return distance >= commitDistance
    }

    /// 往不能去的方向拉：越拉越動不了，永遠不會超過 `resistLimit`
    public static func resisted(_ distance: Double) -> Double {
        guard distance > 0 else { return 0 }
        return resistLimit * (1 - 1 / (distance * resistRatio / resistLimit + 1))
    }
}

/// 什麼時候請 iOS 跳評分視窗，照《蔬菜家族 App 共用基本元素規格》的預設：
/// 裝滿 3 天、存好行程至少 5 次、這個版本還沒請過。「剛存好一筆行程」由呼叫的地方保證。
/// iOS 一年最多讓同一個 app 跳三次，請了也可能不跳，所以同一版只請一次，不浪費額度。
public enum ReviewTiming {
    public static let minDays = 3
    public static let minSaves = 5
    private static let secondsPerDay: TimeInterval = 86_400

    public static func shouldAsk(_ settings: AppSettings, version: String, now: Date) -> Bool {
        guard !version.isEmpty, settings.reviewAskedVersion != version else { return false }
        guard settings.savedEventCount >= minSaves else { return false }
        guard let first = settings.firstOpenedAt else { return false }
        return now.timeIntervalSince(first) >= Double(minDays) * secondsPerDay
    }
}
