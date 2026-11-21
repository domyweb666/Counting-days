import SwiftUI
import CalendarCore

/// 清單：上面小月曆只有色塊，下面是「接下來」
struct ListModeView: View {
    let vm: CalendarViewModel
    let actions: CalendarActions

    /// 這個畫面的內容離螢幕邊緣 20：外層已經有月曆的 8，這裡再補 12
    private let inset = DT.Size.screenMargin - Theme.Grid.margin

    var body: some View {
        ScrollView {
            VStack(spacing: DT.Space.s3) {
                miniCalendar
                if let sel = vm.selected, let day = vm.day(for: sel) {
                    DayPanel(vm: vm, day: day, actions: actions)
                        .padding(.horizontal, inset - DT.Space.s1)
                }
                Text("接下來")
                    .dFont(DT.TypeScale.title3)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DT.Space.s2)
                    .padding(.horizontal, inset + DT.Space.s1)
                    .accessibilityAddTraits(.isHeader)
                if vm.upcoming.isEmpty {
                    EmptyStateView(
                        systemImage: "calendar",
                        title: "接下來沒有行程",
                        message: "按右上角的「+」新增一個，它會寫進 iPhone 的行事曆。"
                    )
                }
                ForEach(vm.upcoming) { card in
                    UpcomingCardView(vm: vm, card: card)
                        .padding(.horizontal, inset)
                }
            }
            .padding(.bottom, DT.Space.s8)
        }
        // 小月曆換月時輕輕點一下
        .sensoryFeedback(.selection, trigger: vm.listMonth)
    }

    private var miniCalendar: some View {
        VStack(spacing: DT.Space.s2) {
            HStack {
                Button { vm.shiftListMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: DT.Size.touch, height: DT.Size.touch)
                }
                .accessibilityLabel("上個月")
                Spacer()
                Text("\(vm.titleYearText) 年 \(vm.titleMonthText)")
                    .dFont(DT.TypeScale.callout)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { vm.shiftListMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: DT.Size.touch, height: DT.Size.touch)
                }
                .accessibilityLabel("下個月")
            }
            .foregroundStyle(Theme.accent)
            HStack(spacing: 0) {
                ForEach(vm.weekdaySymbols, id: \.self) { s in
                    Text(s).dFont(DT.TypeScale.caption).foregroundStyle(Theme.sub).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: DT.Space.s1) {
                ForEach(vm.listWeeks) { week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.days.enumerated()), id: \.element.id) { col, day in
                            Button { vm.toggle(day.date) } label: {
                                MiniCell(vm: vm, week: week, col: col, day: day)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(vm.accessibilityLabel(for: day))
                        }
                    }
                }
            }
            // 換月時格子淡入淡出，不直接換掉
            .animation(Theme.Motion.change, value: vm.listMonth)
        }
        .padding(.top, DT.Space.s1)
        .padding(.horizontal, DT.Space.s3)
        .padding(.bottom, DT.Space.s4)
        .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
        .padding(.horizontal, inset)
    }
}

struct MiniCell: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let col: Int
    let day: DayModel

    private let side: CGFloat = 36
    /// 今天的綠框和色塊之間那條縫的寬度
    private let todayGap: CGFloat = 2

    private var segment: BandSegment? {
        week.segments.first { $0.band.lane == 0 && col >= $0.startCol && col <= $0.endCol }
    }

    var body: some View {
        let isSelected = vm.selected == day.date
        let seg = segment
        let label = Text(vm.cellLabel(day.date))
            .sFont(vm.dayNumber(day.date) == 1 ? 12 : 15, .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        ZStack {
            if let seg {
                let lead: CGFloat = (col == seg.startCol && seg.startsHere) || col == 0 ? DT.Radius.md : 0
                let trail: CGFloat = (col == seg.endCol && seg.endsHere) || col == 6 ? DT.Radius.md : 0
                UnevenRoundedRectangle(
                    topLeadingRadius: lead, bottomLeadingRadius: lead,
                    bottomTrailingRadius: trail, topTrailingRadius: trail
                )
                .fill(seg.isPast ? Theme.muted : vm.color(seg.band.categoryID))
                label.foregroundStyle(seg.isPast ? Theme.sub : vm.onColor(seg.band.categoryID))
            } else if let head = day.head {
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .fill(day.isPast ? Theme.muted : vm.color(head.categoryID))
                    .frame(width: side)
                label.foregroundStyle(day.isPast ? Theme.sub : vm.onColor(head.categoryID))
            } else {
                label.foregroundStyle(
                    day.holidays.isEmpty ? (day.isPast ? Theme.tertiary : Theme.ink) : Theme.destructive
                )
            }
            if day.isToday {
                if seg != nil || day.head != nil {
                    // 今天有色塊：綠框和色塊中間壓一條卡片底色的縫，兩個深色才不會黏在一起
                    ZStack {
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .strokeBorder(Theme.card, lineWidth: Theme.Grid.ring + todayGap)
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .strokeBorder(Theme.accent, lineWidth: Theme.Grid.ring)
                    }
                    .frame(width: side)
                } else {
                    Circle().strokeBorder(Theme.accent, lineWidth: Theme.Grid.ring).frame(width: side)
                }
            }
            if isSelected, !day.isToday {
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .strokeBorder(Theme.accent, lineWidth: Theme.Grid.ring)
                    .frame(width: side)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: side)
        .opacity(vm.isInListMonth(day.date) ? 1 : 0.35)
        .contentShape(Rectangle())
    }
}

struct UpcomingCardView: View {
    let vm: CalendarViewModel
    let card: UpcomingCard

    var body: some View {
        Button {
            vm.jump(to: max(card.date, vm.today))
        } label: {
            HStack(spacing: DT.Space.s3) {
                block
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dFont(DT.TypeScale.headline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let sub {
                        Text(sub)
                            .dFont(DT.TypeScale.footnote)
                            .foregroundStyle(Theme.sub)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Text(card.awayText).dFont(DT.TypeScale.subheadline).foregroundStyle(Theme.sub)
            }
            .padding(.vertical, DT.Space.s3)
            .padding(.horizontal, DT.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private var title: String {
        switch card.kind {
        case .day(let d): return d.head?.event.title ?? ""
        case .band(let b): return b.event.title
        }
    }

    private var sub: String? {
        switch card.kind {
        case .day(let d):
            guard !d.rest.isEmpty else { return nil }
            return "還有 " + d.rest.map { $0.event.title }.joined(separator: "、")
        case .band(let b):
            var parts = ["\(b.totalDays) 天"]
            if b.event.hasLocation, let loc = b.event.location { parts.append(loc) }
            return parts.joined(separator: " · ")
        }
    }

    private var block: some View {
        let categoryID: String
        let big: String
        let small: String
        let bigStyle: DomyTypeStyle
        switch card.kind {
        case .day(let d):
            categoryID = d.head?.categoryID ?? ""
            big = String(vm.dayNumber(d.date))
            small = "週" + vm.dow(d.date)
            bigStyle = DT.TypeScale.title2
        case .band(let b):
            categoryID = b.categoryID
            big = vm.md(b.firstDay)
            small = "到 " + vm.md(b.lastDay)
            bigStyle = DT.TypeScale.headline
        }
        return VStack(spacing: 0) {
            Text(big).dFont(bigStyle).lineLimit(1).minimumScaleFactor(0.6)
            Text(small).dFont(DT.TypeScale.caption).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(vm.onColor(categoryID))
        .frame(width: 56, height: 56)
        .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(vm.color(categoryID)))
    }
}
