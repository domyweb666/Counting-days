import SwiftUI
import CalendarCore

/// 畫面上各處共用的動作
struct CalendarActions {
    var open: (CalEvent) -> Void
    var add: (Date) -> Void
    var shortName: (CalEvent) -> Void
}

/// 日期數字：今天是黑底白字的圓，被選的有藍框
struct DayNumber: View {
    let vm: CalendarViewModel
    let day: DayModel
    var height: CGFloat = 30
    var fontSize: CGFloat = 15

    private var isSelected: Bool { vm.selected == day.date }

    private var foreground: Color {
        if day.isToday { return Theme.inkInverse }
        if !day.holidays.isEmpty { return Theme.holiday }
        return day.isPast ? Theme.sub : Theme.ink
    }

    var body: some View {
        let label = vm.cellLabel(day.date)
        Text(label)
            .sFont(label.count > 2 ? fontSize - 3 : fontSize, .bold)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(day.isToday ? Theme.ink : Color.clear))
            .overlay(Capsule().strokeBorder(isSelected ? Theme.select : Color.clear, lineWidth: 3))
    }
}

/// 日期下面的小字：節日、節氣、農曆
struct SublineText: View {
    let subline: Subline?

    var body: some View {
        Text(subline?.text ?? " ")
            .sFont(10, .medium)
            .foregroundStyle(subline?.isHoliday == true ? Theme.holiday : Theme.sub)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 收合的一週：只剩日期數字與類別色點
struct CollapsedWeek: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let actions: CalendarActions

    var body: some View {
        HStack(spacing: 3) {
            ForEach(week.days) { day in
                Button {
                    vm.toggle(day.date)
                } label: {
                    VStack(spacing: 2) {
                        DayNumber(vm: vm, day: day, height: 24, fontSize: 13)
                        if let sub = vm.subline(for: day) {
                            SublineText(subline: sub)
                        }
                        dots(day)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .contextMenu {
                    Button("新增行程", systemImage: "plus") { actions.add(day.date) }
                }
            }
        }
    }

    private func dots(_ day: DayModel) -> some View {
        HStack(spacing: 2) {
            ForEach(day.events.prefix(4)) { e in
                Circle().fill(vm.color(e.categoryID)).frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
    }
}

/// 展開的一週（A 彈性週、D 主事件共用）
struct ExpandedWeek: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let showAll: Bool
    let actions: CalendarActions

    private var hasSubline: Bool {
        week.days.contains { vm.subline(for: $0) != nil }
    }

    private var lanes: [Int] {
        Array(Set(week.segments.map { $0.band.lane })).sorted()
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(week.days) { day in
                    Button {
                        vm.toggle(day.date)
                    } label: {
                        VStack(spacing: 0) {
                            DayNumber(vm: vm, day: day)
                            if hasSubline {
                                SublineText(subline: vm.subline(for: day))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(vm.accessibilityLabel(for: day))
                    .contextMenu {
                        Button("新增行程", systemImage: "plus") { actions.add(day.date) }
                    }
                }
            }
            ForEach(lanes, id: \.self) { lane in
                BandLaneRow(vm: vm, week: week, segments: week.segments.filter { $0.band.lane == lane }, thin: lane >= 2)
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(week.days) { day in
                    Button {
                        vm.toggle(day.date)
                    } label: {
                        DayColumn(vm: vm, day: day, showAll: showAll)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

/// 一格裡的事件：A 方式列出全部，D 方式只有主事件加小色塊
struct DayColumn: View {
    let vm: CalendarViewModel
    let day: DayModel
    let showAll: Bool

    static let maxChips = 5
    static let maxPips = 4

    var body: some View {
        VStack(spacing: 3) {
            if showAll {
                ForEach(day.events.prefix(Self.maxChips)) { e in
                    EventChip(label: e.label, color: vm.color(e.categoryID), isPast: day.isPast, fontSize: 13)
                }
                if day.events.count > Self.maxChips {
                    Text("還有\(day.events.count - Self.maxChips)件")
                        .sFont(11, .bold)
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else if let head = day.head {
                EventChip(label: head.label, color: vm.color(head.categoryID), isPast: day.isPast, fontSize: 14)
                PipRow(vm: vm, events: day.rest, isPast: day.isPast)
            }
        }
        .padding(.horizontal, 1)
    }
}

struct EventChip: View {
    let label: String
    let color: Color
    let isPast: Bool
    let fontSize: CGFloat

    var body: some View {
        Text(label)
            .sFont(fontSize, .bold)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .foregroundStyle(isPast ? Theme.pastFg : Color.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(isPast ? Theme.pastBg : color))
    }
}

/// 其餘事件：每件一個 8 pt 小色塊，最多 4 個，再多加「+」
struct PipRow: View {
    let vm: CalendarViewModel
    let events: [ClassifiedEvent]
    let isPast: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(events.prefix(DayColumn.maxPips)) { e in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPast ? Theme.sub : vm.color(e.categoryID))
                    .frame(width: 8, height: 8)
            }
            if events.count > DayColumn.maxPips {
                Text("+").sFont(10, .heavy).foregroundStyle(Theme.sub)
            }
        }
        .frame(minHeight: 8)
    }
}

/// 跨日事件的色帶。同一條裡可能有前後兩段不重疊的事件。
struct BandLaneRow: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let segments: [BandSegment]
    let thin: Bool

    private var height: CGFloat { thin ? 4 : 36 }

    var body: some View {
        GeometryReader { geo in
            let colW = (geo.size.width - 18) / 7
            ForEach(segments) { seg in
                segmentView(seg)
                    .frame(width: CGFloat(seg.span) * colW + CGFloat(seg.span - 1) * 3, height: height)
                    .offset(x: CGFloat(seg.startCol) * (colW + 3))
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func segmentView(_ seg: BandSegment) -> some View {
        let fill = seg.isPast ? Theme.pastBg : vm.color(seg.band.categoryID)
        let lead: CGFloat = seg.startsHere ? (thin ? 2 : 10) : 0
        let trail: CGFloat = seg.endsHere ? (thin ? 2 : 10) : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: lead, bottomLeadingRadius: lead,
            bottomTrailingRadius: trail, topTrailingRadius: trail
        )
        if thin {
            shape.fill(fill).accessibilityHidden(true)
        } else {
            Button {
                vm.toggle(week.days[seg.startCol].date)
            } label: {
                HStack(spacing: 4) {
                    Text(seg.band.event.title)
                        .sFont(16, .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if seg.span >= 3, let right = rightText(seg) {
                        Text(right).sFont(13, .bold).lineLimit(1)
                    }
                }
                .foregroundStyle(seg.isPast ? Theme.pastFg : Color.white)
                .padding(.horizontal, seg.span == 1 ? 4 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(fill))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(seg.band.event.title)，共 \(seg.band.totalDays) 天")
        }
    }

    private func rightText(_ seg: BandSegment) -> String? {
        if seg.startsHere { return "共 \(seg.band.totalDays) 天" }
        if seg.endsHere { return "\(vm.md(seg.band.lastDay)) 結束" }
        return nil
    }
}
