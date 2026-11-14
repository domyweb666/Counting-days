import Foundation

/// 從系統行事曆讀出來的一筆事件（已經脫離 EventKit，方便測試）。
public struct CalEvent: Identifiable, Hashable, Sendable {
    /// 單次發生的識別碼（重複事件每次發生都不同）。
    public var id: String
    /// 整個系列共用的識別碼，置頂、短名、倒數都以它為鍵。
    public var seriesID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var location: String?
    public var hasAttendees: Bool
    public var isRecurring: Bool
    /// 每天重複的例行事件：月檢視不顯示，只在點開當天時出現。
    public var isDailyRoutine: Bool

    public init(
        id: String,
        seriesID: String? = nil,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        location: String? = nil,
        hasAttendees: Bool = false,
        isRecurring: Bool = false,
        isDailyRoutine: Bool = false
    ) {
        self.id = id
        self.seriesID = seriesID ?? id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.location = location
        self.hasAttendees = hasAttendees
        self.isRecurring = isRecurring
        self.isDailyRoutine = isDailyRoutine
    }

    public var hasLocation: Bool {
        guard let location else { return false }
        return !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct EventCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// 例如 "#6F5F8F"
    public var colorHex: String
    /// 挑主事件時優先（預設：看診、行程）。
    public var isPriority: Bool

    public init(id: String, name: String, colorHex: String, isPriority: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isPriority = isPriority
    }
}

public struct KeywordRule: Codable, Hashable, Sendable {
    public var keyword: String
    public var categoryID: String

    public init(keyword: String, categoryID: String) {
        self.keyword = keyword
        self.categoryID = categoryID
    }
}

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case flex = "A"
    case list = "B"
    case strips = "C"
    case head = "D"

    public var label: String {
        switch self {
        case .flex: return "彈性週"
        case .list: return "清單"
        case .strips: return "週條"
        case .head: return "主事件"
        }
    }
}

/// app 自己存的資料：只存系統行事曆沒有的東西。
public struct AppSettings: Codable, Equatable, Sendable {
    public var categories: [EventCategory]
    /// 行事曆識別碼 → 類別識別碼
    public var calendarCategory: [String: String]
    public var keywordRules: [KeywordRule]
    public var holidayCalendarIDs: Set<String>
    public var hiddenCalendarIDs: Set<String>
    /// 被置頂的事件系列
    public var pinned: Set<String>
    /// 事件系列 → 短名
    public var shortNames: [String: String]
    /// 倒數日（事件系列識別碼，依加入順序）
    public var countdowns: [String]
    /// 最上層的檢視：月、時間表、週、3 天、天
    public var view: ViewKind
    /// 月曆樣式
    public var mode: DisplayMode
    public var weekStartsOnMonday: Bool
    public var showLunar: Bool
    public var didAutoDetectHolidays: Bool

    public static let fallbackCategoryID = "trip"

    public static let defaultCategories: [EventCategory] = [
        EventCategory(id: "work", name: "工作", colorHex: "#6F5F8F"),
        EventCategory(id: "trip", name: "行程", colorHex: "#4B6C8F", isPriority: true),
        EventCategory(id: "med", name: "看診", colorHex: "#A65F45", isPriority: true),
        EventCategory(id: "errand", name: "辦事", colorHex: "#7A6A3A")
    ]

    public init(
        categories: [EventCategory] = AppSettings.defaultCategories,
        calendarCategory: [String: String] = [:],
        keywordRules: [KeywordRule] = [],
        holidayCalendarIDs: Set<String> = [],
        hiddenCalendarIDs: Set<String> = [],
        pinned: Set<String> = [],
        shortNames: [String: String] = [:],
        countdowns: [String] = [],
        view: ViewKind = .month,
        mode: DisplayMode = .flex,
        weekStartsOnMonday: Bool = false,
        showLunar: Bool = true,
        didAutoDetectHolidays: Bool = false
    ) {
        self.categories = categories
        self.calendarCategory = calendarCategory
        self.keywordRules = keywordRules
        self.holidayCalendarIDs = holidayCalendarIDs
        self.hiddenCalendarIDs = hiddenCalendarIDs
        self.pinned = pinned
        self.shortNames = shortNames
        self.countdowns = countdowns
        self.view = view
        self.mode = mode
        self.weekStartsOnMonday = weekStartsOnMonday
        self.showLunar = showLunar
        self.didAutoDetectHolidays = didAutoDetectHolidays
    }

    // 之後版本加欄位時，舊資料少了欄位也要讀得回來，所以每個欄位都給預設值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        categories = try c.decodeIfPresent([EventCategory].self, forKey: .categories) ?? d.categories
        calendarCategory = try c.decodeIfPresent([String: String].self, forKey: .calendarCategory) ?? d.calendarCategory
        keywordRules = try c.decodeIfPresent([KeywordRule].self, forKey: .keywordRules) ?? d.keywordRules
        holidayCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .holidayCalendarIDs) ?? d.holidayCalendarIDs
        hiddenCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendarIDs) ?? d.hiddenCalendarIDs
        pinned = try c.decodeIfPresent(Set<String>.self, forKey: .pinned) ?? d.pinned
        shortNames = try c.decodeIfPresent([String: String].self, forKey: .shortNames) ?? d.shortNames
        countdowns = try c.decodeIfPresent([String].self, forKey: .countdowns) ?? d.countdowns
        view = try c.decodeIfPresent(ViewKind.self, forKey: .view) ?? d.view
        mode = try c.decodeIfPresent(DisplayMode.self, forKey: .mode) ?? d.mode
        weekStartsOnMonday = try c.decodeIfPresent(Bool.self, forKey: .weekStartsOnMonday) ?? d.weekStartsOnMonday
        showLunar = try c.decodeIfPresent(Bool.self, forKey: .showLunar) ?? d.showLunar
        didAutoDetectHolidays = try c.decodeIfPresent(Bool.self, forKey: .didAutoDetectHolidays) ?? d.didAutoDetectHolidays
        if categories.isEmpty { categories = d.categories }
    }

    public func category(id: String) -> EventCategory {
        categories.first { $0.id == id }
            ?? categories.first { $0.id == AppSettings.fallbackCategoryID }
            ?? categories[0]
    }
}

// MARK: - 版面用的模型

public struct ClassifiedEvent: Identifiable, Hashable, Sendable {
    public var event: CalEvent
    public var categoryID: String
    /// 月檢視格子裡顯示的字
    public var label: String
    public var isPinned: Bool

    public var id: String { event.id }
}

/// 跨日事件
public struct Band: Identifiable, Hashable, Sendable {
    public var event: CalEvent
    public var categoryID: String
    public var firstDay: Date
    public var lastDay: Date
    public var totalDays: Int
    /// 重疊時排在第幾條（0、1 是完整色帶，2 以後是細線）
    public var lane: Int

    public var id: String { event.id }
}

/// 跨日事件在某一週裡的那一段
public struct BandSegment: Identifiable, Hashable, Sendable {
    public var band: Band
    /// 這一週內的起訖欄（0...6）
    public var startCol: Int
    public var endCol: Int
    public var startsHere: Bool
    public var endsHere: Bool
    public var isPast: Bool

    public var id: String { band.id + "@\(startCol)" }
    public var span: Int { endCol - startCol + 1 }
}

public struct DayModel: Identifiable, Hashable, Sendable {
    public var date: Date
    /// 單日事件，依時間排序（不含跨日、節日、每日例行）
    public var events: [ClassifiedEvent]
    public var routines: [ClassifiedEvent]
    public var head: ClassifiedEvent?
    public var rest: [ClassifiedEvent]
    public var holidays: [String]
    public var bands: [Band]
    public var isPast: Bool
    public var isToday: Bool

    public var id: Date { date }
    public var hasEvents: Bool { !events.isEmpty }
    /// 這一天要算的件數（含跨日）
    public var count: Int { events.count + bands.count }
}

public struct WeekModel: Identifiable, Hashable, Sendable {
    public var days: [DayModel]
    public var segments: [BandSegment]
    public var isAllPast: Bool

    public var id: Date { days[0].date }
    public var hasAnything: Bool { days.contains { $0.hasEvents } || !segments.isEmpty }
    /// 彈性週、主事件兩種方式：過去的週與沒事的週收成一行
    public var isCollapsed: Bool { isAllPast || !hasAnything }
}
