import SwiftUI
import CalendarCore

/// 週條：一週一橫條，沒事的日子縮窄，有事的日子撐開
struct StripWeek: View {
    let vm: CalendarViewModel
    let week: WeekModel
    let actions: CalendarActions

    var body: some View {
        if week.isCollapsed {
            emptyRow
        } else {
            FlexRow(spacing: DT.Space.s1) {
                ForEach(vm.builder.stripItems(for: week)) { item in
                    itemView(item)
                }
            }
            .frame(minHeight: 64)
            .padding(.horizontal, DT.Space.s1)
        }
    }

    /// 整週沒事（或整週已過去）：一行 7 個等寬的日期
    private var emptyRow: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                Button {
                    vm.toggle(day.date)
                } label: {
                    VStack(spacing: 1) {
                        DayNumber(vm: vm, day: day, height: Theme.Grid.dayCircleSmall, fontSize: 13)
                        Text(vm.subline(for: day)?.text ?? vm.dow(day.date))
                            .sFont(10, .medium)
                            .foregroundStyle(day.holidays.isEmpty ? Theme.sub : Theme.destructive)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 2) {
                            ForEach(day.events.prefix(4)) { e in
                                Circle().fill(vm.color(e.categoryID)).frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: DT.Size.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .contextMenu {
                    Button("新增行程", systemImage: "plus") { actions.add(day.date) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
        .padding(.horizontal, DT.Space.s1)
    }

    @ViewBuilder
    private func itemView(_ item: StripItem) -> some View {
        switch item {
        case .narrow(let day):
            Button { vm.toggle(day.date) } label: { narrow(day) }
                .buttonStyle(PressStyle())
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(0)
        case .card(let day):
            Button { vm.toggle(day.date) } label: { card(day) }
                .buttonStyle(PressStyle())
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(2)
        case .compact(let day):
            Button { vm.toggle(day.date) } label: { compact(day) }
                .buttonStyle(PressStyle())
                .accessibilityLabel(vm.accessibilityLabel(for: day))
                .flex(1)
        case .trip(let seg):
            Button { vm.toggle(week.days[seg.startCol].date) } label: { trip(seg) }
                .buttonStyle(PressStyle())
                .flex(CGFloat(seg.span))
        }
    }

    private func selectionRing(_ day: DayModel) -> some View {
        RoundedRectangle(cornerRadius: DT.Radius.lg)
            .strokeBorder(vm.selected == day.date ? Theme.accent : Color.clear, lineWidth: Theme.Grid.ring)
    }

    private func narrow(_ day: DayModel) -> some View {
        VStack(spacing: 2) {
            DayNumber(vm: vm, day: day, height: Theme.Grid.dayCircleSmall, fontSize: 13)
            Text(vm.dow(day.date)).sFont(10, .medium).foregroundStyle(Theme.sub)
        }
        .frame(width: Theme.Grid.dayCircle)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func dateLabel(_ day: DayModel, short: Bool) -> String {
        let base = short ? "\(vm.dayNumber(day.date)) \(vm.dow(day.date))" : "\(vm.dayNumber(day.date)) 週\(vm.dow(day.date))"
        if !short, let h = day.holidays.first { return base + " · " + h }
        return base
    }

    private func dateColor(_ day: DayModel) -> Color {
        day.isPast ? Theme.sub : Theme.ink
    }

    /// 卡片左上角的日期。今天換成綠色膠囊，前面寫「今天」，跟其他樣式「今天是綠色實心」同一套
    @ViewBuilder
    private func dateTag(_ day: DayModel, short: Bool) -> some View {
        if day.isToday {
            // 窄卡放不下「今天 18 三」，短版只寫「今天 18」
            Text(short ? "今天 \(vm.dayNumber(day.date))" : "今天 " + dateLabel(day, short: false))
                .dFont(DT.TypeScale.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, DT.Space.s2)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.accent))
        } else {
            Text(dateLabel(day, short: short))
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(dateColor(day))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 跨日色帶裡如果有今天，是第幾欄
    private func todayColumn(in seg: BandSegment) -> Int? {
        (seg.startCol...seg.endCol).first { week.days[$0].isToday }
    }

    private func card(_ day: DayModel) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            dateTag(day, short: false)
            ForEach(day.events.prefix(6)) { e in
                let isHead = e.id == day.head?.id
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.isPast ? Theme.tertiary : vm.color(e.categoryID))
                        .frame(width: Theme.Grid.pip, height: Theme.Grid.pip)
                    Text(e.event.title)
                        .dFont(isHead ? DT.TypeScale.headline : DT.TypeScale.subheadline)
                        .multilineTextAlignment(.leading)
                }
            }
            if day.events.count > 6 {
                Text("還有 \(day.events.count - 6) 件").dFont(DT.TypeScale.caption).foregroundStyle(Theme.sub)
            }
        }
        .foregroundStyle(day.isPast ? Theme.sub : Theme.ink)
        .padding(.vertical, DT.Space.s2)
        .padding(.horizontal, DT.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(day.isPast ? Theme.muted : Theme.card))
        .overlay(selectionRing(day))
        .contentShape(Rectangle())
    }

    private func compact(_ day: DayModel) -> some View {
        VStack(spacing: DT.Space.s1) {
            dateTag(day, short: true)
            if let head = day.head {
                EventChip(vm: vm, label: head.label, categoryID: head.categoryID, isPast: day.isPast)
            }
            PipRow(vm: vm, events: day.rest, isPast: day.isPast)
        }
        .padding(.top, 6)
        .padding(.horizontal, Theme.Grid.gap)
        .padding(.bottom, DT.Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: DT.Radius.lg).fill(Theme.card))
        .overlay(selectionRing(day))
        .contentShape(Rectangle())
    }

    private func trip(_ seg: BandSegment) -> some View {
        let lead: CGFloat = seg.startsHere ? DT.Radius.lg : 0
        let trail: CGFloat = seg.endsHere ? DT.Radius.lg : 0
        let from = week.days[seg.startCol].date
        let to = week.days[seg.endCol].date
        let range = seg.span == 1
            ? "\(vm.dayNumber(from)) 週\(vm.dow(from))"
            : "\(vm.cellLabel(from)) 週\(vm.dow(from)) → \(vm.dayNumber(to)) 週\(vm.dow(to))"
        let todayCol = todayColumn(in: seg)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DT.Space.s2) {
                Text(range).dFont(DT.TypeScale.caption).lineLimit(1).minimumScaleFactor(0.7)
                if let todayCol {
                    // 色帶本身有顏色，膠囊用卡片底色配綠字才分得出來
                    Text("今天 \(vm.dayNumber(week.days[todayCol].date))")
                        .dFont(DT.TypeScale.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.strong)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DT.Space.s2)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.card))
                }
            }
            Text(seg.band.event.title)
                .dFont(seg.span == 1 ? DT.TypeScale.subheadline : DT.TypeScale.title2)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(seg.isPast ? Theme.sub : vm.onColor(seg.band.categoryID))
        .padding(.vertical, DT.Space.s2)
        .padding(.horizontal, seg.span == 1 ? 6 : DT.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: lead, bottomLeadingRadius: lead,
                bottomTrailingRadius: trail, topTrailingRadius: trail
            )
            .fill(seg.isPast ? Theme.muted : vm.color(seg.band.categoryID))
        )
        .contentShape(Rectangle())
        .accessibilityLabel("\(seg.band.event.title)，共 \(seg.band.totalDays) 天")
    }
}
