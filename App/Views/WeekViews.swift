import SwiftUI
import CalendarCore

/// 畫面上各處共用的動作
struct CalendarActions {
    var open: (CalEvent) -> Void
    var add: (Date) -> Void
    var shortName: (CalEvent) -> Void
    /// 碰到要完整版才能用的東西，請畫面打開「完整版」頁
    var needFullVersion: (FullVersionReason) -> Void
    /// 長按選單的「分享」：打開 iPhone 的分享面板，送出時間標題加 Google 日曆連結
    var share: (CalEvent) -> Void = { _ in }
}

/// 日期數字：今天是產品色實心圓，被選的有產品色外框
struct DayNumber: View {
    let vm: CalendarViewModel
    let day: DayModel
    var height: CGFloat = Theme.Grid.dayCircle
    var fontSize: CGFloat = 15

    private var isSelected: Bool { vm.selected == day.date }

    private var foreground: Color {
        if day.isToday { return Theme.onAccent }
        if !day.holidays.isEmpty { return Theme.destructive }
        return day.isPast ? Theme.tertiary : Theme.ink
    }

    var body: some View {
        let label = vm.cellLabel(day.date)
        Text(label)
            .sFont(label.count > 2 ? fontSize - 3 : fontSize, .semibold)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Theme.Grid.gap)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(day.isToday ? Theme.accent : Color.clear))
            .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: Theme.Grid.ring))
    }
}

/// 日期下面的小字：節日、節氣、農曆
struct SublineText: View {
    let subline: Subline?

    var body: some View {
        Text(subline?.text ?? " ")
            .sFont(10, .medium)
            .foregroundStyle(subline?.isHoliday == true ? Theme.destructive : Theme.sub)
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
        HStack(spacing: Theme.Grid.gap) {
            ForEach(week.days) { day in
                Button {
                    vm.toggle(day.date)
                } label: {
                    VStack(spacing: 2) {
                        DayNumber(vm: vm, day: day, height: Theme.Grid.dayCircleSmall, fontSize: 13)
                        if let sub = vm.subline(for: day) {
                            SublineText(subline: sub)
                        }
                        dots(day)
                    }
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
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
                Circle().fill(vm.color(e.categoryID)).frame(width: Theme.Grid.dot, height: Theme.Grid.dot)
            }
        }
        .frame(height: Theme.Grid.dot)
    }
}

/// 展開的一週（彈性週、主事件共用）
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
        VStack(spacing: DT.Space.s1) {
            HStack(spacing: Theme.Grid.gap) {
                ForEach(week.days) { day in
                    Button {
                        vm.toggle(day.date)
                    } label: {
                        VStack(spacing: 1) {
                            DayNumber(vm: vm, day: day)
                            if hasSubline {
                                SublineText(subline: vm.subline(for: day))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(vm.accessibilityLabel(for: day))
                    .contextMenu {
                        Button("新增行程", systemImage: "plus") { actions.add(day.date) }
                    }
                }
            }
            ForEach(lanes, id: \.self) { lane in
                BandLaneRow(vm: vm, week: week, segments: week.segments.filter { $0.band.lane == lane }, thin: BandStyle.isThin(lane: lane, mode: showAll ? .flex : .head))
            }
            HStack(alignment: .top, spacing: Theme.Grid.gap) {
                ForEach(week.days) { day in
                    Button {
                        vm.toggle(day.date)
                    } label: {
                        DayColumn(vm: vm, day: day, showAll: showAll)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.top, DT.Space.s2)
        .padding(.bottom, DT.Space.s3)
        .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
    }
}

/// 一格裡的事件：彈性週列出全部，主事件只有一個色塊加小色塊
struct DayColumn: View {
    let vm: CalendarViewModel
    let day: DayModel
    let showAll: Bool

    static let maxChips = 5
    static let maxPips = 4

    var body: some View {
        VStack(spacing: Theme.Grid.gap) {
            if showAll {
                ForEach(day.events.prefix(Self.maxChips)) { e in
                    EventChip(vm: vm, label: e.label, categoryID: e.categoryID, isPast: day.isPast)
                }
                if day.events.count > Self.maxChips {
                    Text("還有\(day.events.count - Self.maxChips)件")
                        .sFont(11, .semibold)
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else if day.hasEvents {
                // 一天只有一件寫字的：上面有寫字的跨日色帶時，單日的全部縮成小色塊
                if let head = day.headChip {
                    EventChip(vm: vm, label: head.label, categoryID: head.categoryID, isPast: day.isPast)
                }
                PipRow(vm: vm, events: day.headPips, isPast: day.isPast)
            }
        }
        .padding(.horizontal, 1)
    }
}

struct EventChip: View {
    let vm: CalendarViewModel
    let label: String
    let categoryID: String
    let isPast: Bool

    var body: some View {
        Text(label)
            .sFont(13, .semibold)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .foregroundStyle(isPast ? Theme.sub : vm.onColor(categoryID))
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DT.Radius.sm).fill(isPast ? Theme.muted : vm.color(categoryID)))
    }
}

/// 其餘事件：每件一個小色塊，最多 4 個，再多加「+」
struct PipRow: View {
    let vm: CalendarViewModel
    let events: [ClassifiedEvent]
    let isPast: Bool

    var body: some View {
        HStack(spacing: Theme.Grid.gap) {
            ForEach(events.prefix(DayColumn.maxPips)) { e in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPast ? Theme.tertiary : vm.color(e.categoryID))
                    .frame(width: Theme.Grid.pip, height: Theme.Grid.pip)
            }
            if events.count > DayColumn.maxPips {
                Text("+").sFont(10, .bold).foregroundStyle(Theme.sub)
            }
        }
        .frame(minHeight: Theme.Grid.pip)
    }
}

/// 跨日事件的色帶。同一條裡可能有前後兩段不重疊的事件。
struct BandLaneRow: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let segments: [BandSegment]
    let thin: Bool

    private var height: CGFloat { thin ? Theme.Grid.bandThin : Theme.Grid.band }

    var body: some View {
        GeometryReader { geo in
            let gap = Theme.Grid.gap
            let colW = (geo.size.width - gap * 6) / 7
            ForEach(segments) { seg in
                segmentView(seg)
                    .frame(width: CGFloat(seg.span) * colW + CGFloat(seg.span - 1) * gap, height: height)
                    .offset(x: CGFloat(seg.startCol) * (colW + gap))
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func segmentView(_ seg: BandSegment) -> some View {
        let fill = seg.isPast ? Theme.muted : vm.color(seg.band.categoryID)
        let lead: CGFloat = seg.startsHere ? (thin ? 2 : DT.Radius.md) : 0
        let trail: CGFloat = seg.endsHere ? (thin ? 2 : DT.Radius.md) : 0
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
                HStack(spacing: DT.Space.s1) {
                    Text(seg.band.event.title)
                        .dFont(DT.TypeScale.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if seg.span >= 3, let right = rightText(seg) {
                        Text(right).sFont(13, .semibold).lineLimit(1)
                    }
                }
                .foregroundStyle(seg.isPast ? Theme.sub : vm.onColor(seg.band.categoryID))
                .padding(.horizontal, seg.span == 1 ? DT.Space.s1 : DT.Space.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(fill))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(seg.band.event.title)，共 \(seg.band.totalDays) 天")
        }
    }

    private func rightText(_ seg: BandSegment) -> String? {
        if seg.startsHere { return "共 \(seg.band.totalDays) 天" }
        if seg.endsHere { return "\(vm.md(seg.band.lastDay)) 結束" }
        return nil
    }
}
