import Foundation

/// 農曆日期與二十四節氣。
public enum Lunar {
    static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "臘月"
    ]

    public struct LunarDay: Equatable, Sendable {
        public var month: Int
        public var day: Int
        public var isLeapMonth: Bool

        /// 初一顯示月份（例如「三月」「閏三月」），其他日子顯示「初二」「十五」。
        public var shortText: String {
            guard (1...12).contains(month), (1...30).contains(day) else { return "" }
            if day == 1 { return (isLeapMonth ? "閏" : "") + Lunar.monthNames[month - 1] }
            return Lunar.dayNames[day - 1]
        }

        public var fullText: String {
            guard (1...12).contains(month), (1...30).contains(day) else { return "" }
            return "農曆" + (isLeapMonth ? "閏" : "") + Lunar.monthNames[month - 1] + Lunar.dayNames[day - 1]
        }
    }

    public static func lunarDay(for date: Date, timeZone: TimeZone) -> LunarDay {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.month, .day], from: date)
        return LunarDay(month: c.month ?? 0, day: c.day ?? 0, isLeapMonth: c.isLeapMonth ?? false)
    }

    // MARK: 節氣

    /// 依月份排列，每個月兩個節氣：(名稱, 21 世紀的 C 值)
    static let terms: [[(String, Double)]] = [
        [("小寒", 5.4055), ("大寒", 20.12)],
        [("立春", 3.87), ("雨水", 18.73)],
        [("驚蟄", 5.63), ("春分", 20.646)],
        [("清明", 4.81), ("穀雨", 20.1)],
        [("立夏", 5.52), ("小滿", 21.04)],
        [("芒種", 5.678), ("夏至", 21.37)],
        [("小暑", 7.108), ("大暑", 22.83)],
        [("立秋", 7.5), ("處暑", 23.13)],
        [("白露", 7.646), ("秋分", 23.042)],
        [("寒露", 8.318), ("霜降", 23.438)],
        [("立冬", 7.438), ("小雪", 22.36)],
        [("大雪", 7.18), ("冬至", 21.94)]
    ]

    /// 公式算不準的年份：[年: [節氣: 差幾天]]
    static let exceptions: [Int: [String: Int]] = [
        2002: ["立秋": 1],
        2008: ["小滿": 1],
        2016: ["小暑": 1],
        2019: ["小寒": -1],
        2021: ["冬至": -1],
        2026: ["雨水": -1],
        2082: ["大寒": 1],
        2084: ["春分": 1],
        2089: ["霜降": 1, "立冬": 1]
    ]

    /// 這一天是哪個節氣；不是節氣回傳 nil。
    /// 用壽星公式推算，只涵蓋 2001–2099 年，以台灣時間（UTC+8）為準。
    public static func solarTerm(year: Int, month: Int, day: Int) -> String? {
        guard (2001...2099).contains(year), (1...12).contains(month) else { return nil }
        let y = year % 100
        for (name, c) in terms[month - 1] {
            // 一、二月的節氣閏年要用前一年算
            let leap = month <= 2 ? (y - 1) / 4 : y / 4
            var d = Int((Double(y) * 0.2422 + c).rounded(.down)) - leap
            d += exceptions[year]?[name] ?? 0
            if d == day { return name }
        }
        return nil
    }

    public static func solarTerm(for date: Date, calendar: Calendar) -> String? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return solarTerm(year: y, month: m, day: d)
    }
}
