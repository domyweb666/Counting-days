import SwiftUI
import CalendarCore

/// 時間軸：週、3 天、天共用。差別只在一次排幾欄。
/// 左右滑換上一段、下一段；點上面的日期進那一天的「天」檢視。
struct DayGridView: View {
    @Environment(AppModel.self) private var app
    let vm: CalendarViewModel
    let actions: CalendarActions

    // 時間軸專用的尺寸（例外：設計系統沒有時間格線的規格）
    private let gutter: CGFloat = 40
    private let hourHeight: CGFloat = 56
    private let allDayChip: CGFloat = 24
    private let maxAllDayRows = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 手指橫向拖了多遠，畫面跟著移。放手或手勢被取消就自己回到 0。
    @GestureState(resetTransaction: Transaction(animation: Theme.Motion.transition)) private var dragX: CGFloat = 0
    /// 這次往哪邊翻：1 下一段、-1 上一段、0 不是用滑的（按「今天」、點日期）
    @State private var pageDirection = 0
    /// 手指橫向動多遠開始跟著移、滑多遠算要翻頁
    private let swipeStart: CGFloat = 10
    private let swipeCommit: CGFloat = 40

    private var compact: Bool { vm.viewKind == .week }

    /// 橫的比直的多一倍以上才算左右滑，上下捲不算
    private func isSideways(_ move: CGSize) -> Bool {
        abs(move.width) > abs(move.height) * 2
    }

    /// 用滑的翻頁：舊的往手指的方向滑出去，新的從另一邊進來。其他情況（或開了「減少動態效果」）只淡入淡出。
    private var pageTransition: AnyTransition {
        guard !reduceMotion, pageDirection != 0 else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: pageDirection > 0 ? .trailing : .leading),
            removal: .move(edge: pageDirection > 0 ? .leading : .trailing)
        )
    }

    var body: some View {
        let dates = vm.timelineDays
        let days = dates.map { vm.day(for: $0) }
        VStack(spacing: DT.Space.s2) {
            header(dates, days)
                .id(dates.first)
                .transition(pageTransition)
            // 天與 3 天檢視的日期下面有天氣時，放一次來源標示。週檢視一欄太窄，不放天氣。
            if !compact, let credit = app.weatherCredit(for: dates) {
                WeatherCreditLink(credit: credit)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, DT.Space.s3)
            }
            if days.contains(where: { !allDayItems($0).isEmpty }) {
                allDayStrip(days)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    // 換頁時只換裡面的格子，外面的捲動位置留著
                    grid(dates, days)
                        .id(dates.first)
                        .transition(pageTransition)
                }
                .background(Theme.card)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DT.Radius.xl, topTrailingRadius: DT.Radius.xl))
                .onAppear { proxy.scrollTo(startHour(dates), anchor: .top) }
            }
        }
        .offset(x: dragX)
        .simultaneousGesture(
            DragGesture(minimumDistance: swipeStart)
                .updating($dragX) { value, offset, _ in
                    guard !reduceMotion, isSideways(value.translation) else { return }
                    offset = value.translation.width
                }
                // 先記好方向，放手那一刻舊的那一頁才知道要往哪邊出去
                .onChanged { value in
                    guard isSideways(value.translation) else { return }
                    let direction = value.translation.width < 0 ? 1 : -1
                    if pageDirection != direction { pageDirection = direction }
                }
                .onEnded { value in
                    let across = value.translation.width
                    guard isSideways(value.translation), abs(across) >= swipeCommit else {
                        pageDirection = 0
                        return
                    }
                    withAnimation(Theme.Motion.transition) {
                        vm.shiftTimeline(across < 0 ? 1 : -1)
                    } completion: {
                        pageDirection = 0
                    }
                }
        )
        // 換到另一段日期時輕輕點一下
        .sensoryFeedback(.selection, trigger: vm.timelineAnchor)
        .accessibilityAction(named: "上一段") { vm.shiftTimeline(-1) }
        .accessibilityAction(named: "下一段") { vm.shiftTimeline(1) }
    }

    /// 一開始捲到哪個小時：看得到今天就捲到現在前一小時，否則早上 7 點
    private func startHour(_ dates: [Date]) -> Int {
        guard dates.contains(vm.today) else { return 7 }
        return max(0, vm.calendar.component(.hour, from: Date()) - 1)
    }

    // MARK: 上面的日期

    private func header(_ dates: [Date], _ days: [DayModel?]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                let isToday = date == vm.today
                let isHoliday = !(days[index]?.holidays.isEmpty ?? true)
                Button { vm.openDay(date) } label: {
                    VStack(spacing: 2) {
                        Text(compact ? vm.dow(date) : "週" + vm.dow(date))
                            .dFont(DT.TypeScale.caption)
                            .foregroundStyle(isToday ? Theme.strong : Theme.sub)
                        Text(String(vm.dayNumber(date)))
                            .dFont(DT.TypeScale.headline)
                            .foregroundStyle(isToday ? Theme.onAccent : (isHoliday ? Theme.destructive : Theme.ink))
                            .frame(minWidth: DT.Space.s8, minHeight: DT.Space.s8)
                            .background(Circle().fill(isToday ? Theme.accent : Color.clear))
                        if !compact, let forecast = app.forecast(for: date) {
                            HStack(spacing: 2) {
                                Image(systemName: forecast.symbolName)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(WeatherRules.temperatures(forecast))
                                    .sFont(11, .medium)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.sub)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DT.Size.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(headerLabel(date, days[index]))
            }
        }
    }

    /// 日期那一格的朗讀文字，有天氣就接在後面
    private func headerLabel(_ date: Date, _ day: DayModel?) -> String {
        let base = day.map { vm.accessibilityLabel(for: $0) } ?? vm.md(date)
        guard !compact, let forecast = app.forecast(for: date) else { return base }
        return base + "，天氣：" + WeatherRules.line(forecast)
    }

    /// 時間軸上的長按選單。置頂和短名只影響月曆格子，這裡看不出效果，所以不列。
    private func timelineMenu(_ event: CalEvent) -> some View {
        EventMenu(vm: vm, event: event, canPin: false, actions: actions)
    }

    // MARK: 全天

    private struct AllDayItem: Identifiable {
        let id: String
        let title: String
        let categoryID: String
        let event: CalEvent
    }

    private func allDayItems(_ day: DayModel?) -> [AllDayItem] {
        guard let day else { return [] }
        let bands = day.bands.sorted { $0.lane < $1.lane }.map {
            AllDayItem(id: $0.id, title: $0.event.title, categoryID: $0.categoryID, event: $0.event)
        }
        let singles = vm.builder.allDayEvents(for: day).map {
            AllDayItem(id: $0.id, title: $0.event.title, categoryID: $0.categoryID, event: $0.event)
        }
        return bands + singles
    }

    private func allDayStrip(_ days: [DayModel?]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("全天")
                .sFont(10, .medium)
                .foregroundStyle(Theme.sub)
                .frame(width: gutter - 6, height: allDayChip, alignment: .trailing)
                .padding(.trailing, 6)
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let items = allDayItems(day)
                let isPast = day?.isPast ?? false
                VStack(spacing: 2) {
                    ForEach(items.prefix(maxAllDayRows)) { item in
                        Button { actions.open(item.event) } label: {
                            Text(item.title)
                                .sFont(compact ? 10 : 12, .semibold)
                                .lineLimit(1)
                                .foregroundStyle(isPast ? Theme.sub : vm.onColor(item.categoryID))
                                .padding(.horizontal, compact ? 2 : 6)
                                .frame(maxWidth: .infinity, minHeight: allDayChip, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: DT.Radius.sm).fill(isPast ? Theme.muted : vm.color(item.categoryID)))
                        }
                        .buttonStyle(PressStyle())
                        .contextMenu { timelineMenu(item.event) }
                    }
                    if items.count > maxAllDayRows {
                        Text("+\(items.count - maxAllDayRows)")
                            .sFont(10, .semibold)
                            .foregroundStyle(Theme.sub)
                    }
                }
                .padding(.horizontal, 1)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // MARK: 時間格線

    private func grid(_ dates: [Date], _ days: [DayModel?]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .sFont(10, .medium)
                        .foregroundStyle(Theme.sub)
                        .frame(width: gutter - 6, height: hourHeight, alignment: .topTrailing)
                        .offset(y: -6)
                        .opacity(hour == 0 ? 0 : 1)
                        .id(hour)
                }
            }
            .frame(width: gutter, alignment: .leading)
            .accessibilityHidden(true)
            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                column(date, days[index])
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: hourHeight * 24)
        .background(alignment: .top) { hourLines }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                VStack(spacing: 0) {
                    Hairline()
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
        .padding(.leading, gutter)
    }

    private func column(_ date: Date, _ day: DayModel?) -> some View {
        let blocks = day.map { vm.builder.timeBlocks(for: $0) } ?? []
        let isPast = day?.isPast ?? false
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.separator).frame(width: DT.Size.hairline)
                ForEach(blocks) { block in
                    let width = geo.size.width / CGFloat(block.columnCount)
                    let height = CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight
                    Button { actions.open(block.event.event) } label: {
                        blockView(block, height: height, isPast: isPast)
                    }
                    .buttonStyle(PressStyle())
                    .contextMenu { timelineMenu(block.event.event) }
                    .frame(width: max(width - 1, 0), height: max(height - 1, 0))
                    .offset(x: CGFloat(block.column) * width + 1, y: CGFloat(block.startMinute) / 60 * hourHeight)
                    .accessibilityLabel("\(block.event.event.title)，\(vm.builder.timeText(block.event.event)) 到 \(vm.builder.endTimeText(block.event.event))")
                }
                if date == vm.today {
                    nowLine(width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func blockView(_ block: TimeBlock, height: CGFloat, isPast: Bool) -> some View {
        let event = block.event.event
        return VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .sFont(compact ? 11 : 13, .semibold)
                .multilineTextAlignment(.leading)
            if !compact, height >= 44 {
                Text("\(vm.builder.timeText(event))–\(vm.builder.endTimeText(event))")
                    .sFont(11, .medium)
                    .opacity(0.85)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isPast ? Theme.sub : vm.onColor(block.event.categoryID))
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DT.Radius.sm).fill(isPast ? Theme.muted : vm.color(block.event.categoryID)))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
        .contentShape(Rectangle())
    }

    private func nowLine(width: CGFloat) -> some View {
        let c = vm.calendar.dateComponents([.hour, .minute], from: Date())
        let y = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 60 * hourHeight
        return ZStack(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: width, height: 2)
            Circle().fill(Theme.accent).frame(width: Theme.Grid.square, height: Theme.Grid.square).offset(x: -4)
        }
        .offset(y: y - 1)
        .accessibilityHidden(true)
    }
}
