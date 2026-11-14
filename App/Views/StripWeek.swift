import SwiftUI
import CalendarCore

/// C 週條：一週一橫條，沒事的日子縮窄，有事的日子撐開
struct StripWeek: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let actions: CalendarActions

    var body: some View {
        if week.isCollapsed {
            emptyRow
        } else {
            FlexRow(spacing: 4) {
                ForEach(vm.builder.stripItems(for: week)) { item in
                    itemView(item)
                }
            }
            .frame(minHeight: 64)
            .padding(.horizontal, 4)
        }
    }

    /// 整週沒事（或整週已過去）：一行 7 個等寬的日期
    private var emptyRow: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                Button {
                    vm.toggle(day.date)
                } label: {
                    VStack(spacing: 0) {
                        DayNumber(vm: vm, day: day, height: 24, fontSize: 14)
                        Text(vm.subline(for: day)?.text ?? vm.dow(day.date))
                            .sFont(11, .medium)
                            .foregroundStyle(day.holidays.isEmpty ? Theme.sub : Theme.holiday)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 2) {
                            ForEach(day.events.prefix(4)) { e in
                                Circle().fill(vm.color(e.categoryID)).frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .contextMenu {
                    Button("新增行程", systemImage: "plus") { actions.add(day.date) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func itemView(_ item: StripItem) -> some View {
        switch item {
        case .narrow(let day):
            Button { vm.toggle(day.date) } label: { narrow(day) }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(0)
        case .card(let day):
            Button { vm.toggle(day.date) } label: { card(day) }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(2)
        case .compact(let day):
            Button { vm.toggle(day.date) } label: { compact(day) }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(1)
        case .trip(let seg):
            Button { vm.toggle(week.days[seg.startCol].date) } label: { trip(seg) }
                .buttonStyle(.plain)
                .flex(CGFloat(seg.span))
        }
    }

    private func selectionRing(_ day: DayModel, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(vm.selected == day.date ? Theme.select : Color.clear, lineWidth: 3)
    }

    private func narrow(_ day: DayModel) -> some View {
        VStack(spacing: 2) {
            DayNumber(vm: vm, day: day, height: 28, fontSize: 14)
            Text(vm.dow(day.date)).sFont(11, .medium).foregroundStyle(Theme.sub)
        }
        .frame(width: 30)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func dateLabel(_ day: DayModel, short: Bool) -> String {
        let base = short ? "\(vm.dayNumber(day.date)) \(vm.dow(day.date))" : "\(vm.dayNumber(day.date)) 週\(vm.dow(day.date))"
        if !short, let h = day.holidays.first { return base + " · " + h }
        return base
    }

    private func card(_ day: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dateLabel(day, short: false))
                .sFont(12, .bold)
                .foregroundStyle(day.isToday ? Theme.select : (day.isPast ? Theme.pastFg : Theme.ink))
                .lineLimit(1)
            ForEach(day.events.prefix(6)) { e in
                let isHead = e.id == day.head?.id
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.isPast ? Theme.sub : vm.color(e.categoryID))
                        .frame(width: 9, height: 9)
                    Text(e.event.title)
                        .sFont(isHead ? 17 : 14, isHead ? .heavy : .bold)
                        .multilineTextAlignment(.leading)
                }
            }
            if day.events.count > 6 {
                Text("還有 \(day.events.count - 6) 件").sFont(12, .bold).foregroundStyle(Theme.sub)
            }
        }
        .foregroundStyle(day.isPast ? Theme.pastFg : Theme.ink)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(day.isPast ? Theme.pastBg : Theme.card))
        .overlay(selectionRing(day, radius: 12))
        .contentShape(Rectangle())
    }

    private func compact(_ day: DayModel) -> some View {
        VStack(spacing: 4) {
            Text(dateLabel(day, short: true))
                .sFont(12, .bold)
                .foregroundStyle(day.isToday ? Theme.select : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let head = day.head {
                EventChip(label: head.label, color: vm.color(head.categoryID), isPast: day.isPast, fontSize: 13)
            }
            PipRow(vm: vm, events: day.rest, isPast: day.isPast)
        }
        .padding(.top, 6)
        .padding(.horizontal, 3)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(selectionRing(day, radius: 12))
        .contentShape(Rectangle())
    }

    private func trip(_ seg: BandSegment) -> some View {
        let lead: CGFloat = seg.startsHere ? 12 : 0
        let trail: CGFloat = seg.endsHere ? 12 : 0
        let from = week.days[seg.startCol].date
        let to = week.days[seg.endCol].date
        let range = seg.span == 1
            ? "\(vm.dayNumber(from)) 週\(vm.dow(from))"
            : "\(vm.cellLabel(from)) 週\(vm.dow(from)) → \(vm.dayNumber(to)) 週\(vm.dow(to))"
        return VStack(alignment: .leading, spacing: 2) {
            Text(range).sFont(13, .bold).lineLimit(1).minimumScaleFactor(0.7)
            Text(seg.band.event.title)
                .sFont(seg.span == 1 ? 15 : 22, .heavy)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(seg.isPast ? Theme.pastFg : Color.white)
        .padding(.vertical, 8)
        .padding(.horizontal, seg.span == 1 ? 6 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: lead, bottomLeadingRadius: lead,
                bottomTrailingRadius: trail, topTrailingRadius: trail
            )
            .fill(seg.isPast ? Theme.pastBg : vm.color(seg.band.categoryID))
        )
        .contentShape(Rectangle())
        .accessibilityLabel("\(seg.band.event.title)，共 \(seg.band.totalDays) 天")
    }
}
