import Foundation

/// 事件歸哪個類別：關鍵字規則優先，其次看行事曆，都沒有就歸「行程」。
public enum Classifier {
    public static func categoryID(for event: CalEvent, settings: AppSettings) -> String {
        let known = Set(settings.categories.map(\.id))
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

/// 每天只有一件主事件。依序比較，分出高下就停：
/// 1. 使用者置頂的
/// 2. 有地點、有受邀者，或屬於優先類別（看診、行程）的
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
