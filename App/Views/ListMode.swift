import SwiftUI
import CalendarCore

/// B 清單：上面小月曆只有色塊，下面是「接下來」
struct ListModeView: View {
    let vm: CalendarViewModel
    let actions: CalendarActions

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                miniCalendar
                if let sel = vm.selected, let day = vm.day(for: sel) {
                    DayPanel(vm: vm, day: day, actions: actions)
                }
                Text("接下來")
                    .sFont(15, .bold)
                    .foregroundStyle(Theme.pastFg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
                if vm.upcoming.isEmpty {
                    Text("接下來沒有行程")
                        .sFont(15, .medium)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                ForEach(vm.upcoming) { card in
                    UpcomingCardView(vm: vm, card: card)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var miniCalendar: some View {
        VStack(spacing: 6) {
            HStack {
                Button { vm.shiftListMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 32)
                }
                .accessibilityLabel("上個月")
                Spacer()
                HStack(spacing: 0) {
                    ForEach(vm.weekdaySymbols, id: \.self) { s in
                        Text(s).sFont(12, .medium).foregroundStyle(Theme.sub).frame(maxWidth: .infinity)
                    }
                }
                Spacer()
                Button { vm.shiftListMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 32)
                }
                .accessibilityLabel("下個月")
            }
            .foregroundStyle(Theme.ink)
            VStack(spacing: 4) {
                ForEach(vm.listWeeks) { week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.days.enumerated()), id: \.element.id) { col, day in
                            Button { vm.toggle(day.date) } label: {
                                MiniCell(vm: vm, week: week, col: col, day: day)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(vm.accessibilityLabel(for: day))
                        }
                    }
                }
            }
            .padding(.horizontal, 44)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .padding(.horizontal, 4)
    }
}

struct MiniCell: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let col: Int
    let day: DayModel

    private var segment: BandSegment? {
        week.segments.first { $0.band.lane == 0 && col >= $0.startCol && col <= $0.endCol }
    }

    var body: some View {
        let isSelected = vm.selected == day.date
        let seg = segment
        let label = Text(vm.cellLabel(day.date))
            .sFont(vm.dayNumber(day.date) == 1 ? 12 : 15, .bold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        ZStack {
            if let seg {
                let lead: CGFloat = (col == seg.startCol && seg.startsHere) || col == 0 ? 10 : 0
                let trail: CGFloat = (col == seg.endCol && seg.endsHere) || col == 6 ? 10 : 0
                UnevenRoundedRectangle(
                    topLeadingRadius: lead, bottomLeadingRadius: lead,
                    bottomTrailingRadius: trail, topTrailingRadius: trail
                )
                .fill(seg.isPast ? Theme.pastBg : vm.color(seg.band.categoryID))
                label.foregroundStyle(seg.isPast ? Theme.pastFg : Color.white)
            } else if let head = day.head {
                RoundedRectangle(cornerRadius: 10)
                    .fill(day.isPast ? Theme.pastBg : vm.color(head.categoryID))
                    .frame(width: 36)
                label.foregroundStyle(day.isPast ? Theme.pastFg : Color.white)
            } else {
                label.foregroundStyle(
                    day.holidays.isEmpty ? (day.isPast ? Theme.sub : Theme.ink) : Theme.holiday
                )
            }
            if day.isToday {
                Circle().strokeBorder(seg == nil ? Theme.ink : Color.white, lineWidth: 3).frame(width: 36)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(seg == nil ? Theme.select : Color.white, lineWidth: 3)
                    .frame(width: 36)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .opacity(vm.isInListMonth(day.date) ? 1 : 0.35)
        .contentShape(Rectangle())
    }
}

struct UpcomingCardView: View {
    let vm: CalendarViewModel
    let card: UpcomingCard

    var body: some View {
        Button {
            let target = max(card.date, vm.today)
            vm.jump(to: target)
        } label: {
            HStack(spacing: 12) {
                block
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .sFont(20, .heavy)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let sub {
                        Text(sub)
                            .sFont(13, .medium)
                            .foregroundStyle(Theme.pastFg)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Text(card.awayText).sFont(15, .bold).foregroundStyle(Theme.pastFg)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
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
        let color: Color
        let big: String
        let small: String
        let bigSize: CGFloat
        switch card.kind {
        case .day(let d):
            color = vm.color(d.head?.categoryID ?? "")
            big = String(vm.dayNumber(d.date))
            small = "週" + vm.dow(d.date)
            bigSize = 24
        case .band(let b):
            color = vm.color(b.categoryID)
            big = vm.md(b.firstDay)
            small = "到 " + vm.md(b.lastDay)
            bigSize = 18
        }
        return VStack(spacing: 0) {
            Text(big).sFont(bigSize, .heavy).lineLimit(1).minimumScaleFactor(0.6)
            Text(small).sFont(12, .bold).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(Color.white)
        .frame(width: 60, height: 60)
        .background(RoundedRectangle(cornerRadius: 12).fill(color))
    }
}
