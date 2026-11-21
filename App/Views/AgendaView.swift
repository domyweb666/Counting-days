import SwiftUI
import CalendarCore

/// 時間表：今天起每件事一列，有起訖時間，一路往下捲
struct AgendaView: View {
    @Environment(AppModel.self) private var app
    let vm: CalendarViewModel
    let actions: CalendarActions

    /// 內容離螢幕邊緣 20：外層已經有月曆的 8，這裡再補 12
    private let inset = DT.Size.screenMargin - Theme.Grid.margin

    var body: some View {
        let days = vm.builder.agendaDays(in: vm.weeks)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DT.Space.s3) {
                // 下面有任何一天顯示了天氣，最上面就放一次來源標示
                if let credit = app.weatherCredit(for: days.map(\.date)) {
                    WeatherCreditLink(credit: credit)
                        .padding(.leading, DT.Size.touch + DT.Space.s3)
                }
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let previous = index > 0 ? days[index - 1].date : nil
                    if let previous, !vm.calendar.isDate(previous, equalTo: day.date, toGranularity: .month) {
                        Text("\(vm.calendar.component(.month, from: day.date))月")
                            .dFont(DT.TypeScale.title2)
                            .foregroundStyle(Theme.ink)
                            .padding(.top, DT.Space.s3)
                            .padding(.leading, DT.Space.s1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if previous.map({ vm.builder.startOfWeek($0) != vm.builder.startOfWeek(day.date) }) ?? true {
                        Text(weekRange(day.date))
                            .dFont(DT.TypeScale.caption)
                            .foregroundStyle(Theme.sub)
                            .padding(.leading, DT.Size.touch + DT.Space.s3)
                    }
                    AgendaDayRow(vm: vm, day: day, actions: actions)
                }
                WideButton(title: "更晚的月份", kind: .secondary) { vm.loadLater() }
                    .padding(.top, DT.Space.s3)
            }
            .padding(.horizontal, inset)
            .padding(.bottom, DT.Space.s8)
        }
    }

    private func weekRange(_ date: Date) -> String {
        let start = vm.builder.startOfWeek(date)
        let end = vm.builder.addDays(start, 6)
        let cal = vm.calendar
        let m1 = cal.component(.month, from: start), d1 = cal.component(.day, from: start)
        let m2 = cal.component(.month, from: end), d2 = cal.component(.day, from: end)
        if m1 == m2 { return "\(m1) 月 \(d1) – \(d2) 日" }
        return "\(m1) 月 \(d1) 日 – \(m2) 月 \(d2) 日"
    }
}

/// 時間表的一天：左邊日期，右邊一張卡列出當天每件事
struct AgendaDayRow: View {
    @Environment(AppModel.self) private var app
    let vm: CalendarViewModel
    let day: DayModel
    let actions: CalendarActions

    var body: some View {
        // 每日例行事件每天都有，列在時間表會把真正的行程淹掉，所以不列
        let rows = vm.builder.detailRows(for: day).filter { $0.kind != .routine }
        HStack(alignment: .top, spacing: DT.Space.s3) {
            Button { vm.openDay(day.date) } label: { dateLabel }
                .buttonStyle(PressStyle())
                .accessibilityLabel(vm.accessibilityLabel(for: day) + "，點一下看當天的時間軸")
            VStack(spacing: 0) {
                if let forecast = app.forecast(for: day.date) {
                    WeatherLine(forecast: forecast)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DT.Space.s2)
                }
                if rows.isEmpty {
                    Text(day.isToday ? "今天沒有行程" : "這天沒有行程")
                        .dFont(DT.TypeScale.subheadline)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0, !row.isBand, !rows[index - 1].isBand {
                        Hairline()
                    }
                    Button { actions.open(row.event) } label: { rowView(row) }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            EventMenu(vm: vm, event: row.event, canPin: row.canPin, actions: actions)
                        }
                }
            }
            .padding(.horizontal, DT.Space.s4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
        }
    }

    private var dateLabel: some View {
        VStack(spacing: 2) {
            Text("週" + vm.dow(day.date))
                .dFont(DT.TypeScale.caption)
                .foregroundStyle(day.isToday ? Theme.strong : Theme.sub)
            Text(String(vm.dayNumber(day.date)))
                .dFont(DT.TypeScale.title3)
                .foregroundStyle(day.isToday ? Theme.onAccent : (day.holidays.isEmpty ? Theme.ink : Theme.destructive))
                .frame(width: DT.Size.buttonCompact, height: DT.Size.buttonCompact)
                .background(Circle().fill(day.isToday ? Theme.accent : Color.clear))
        }
        .frame(width: DT.Size.touch)
        .padding(.top, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowView(_ row: DetailRow) -> some View {
        if case .band(let n, let total) = row.kind {
            Text("\(row.title) · 第 \(n) 天，共 \(total) 天")
                .dFont(DT.TypeScale.callout)
                .foregroundStyle(vm.onColor(row.categoryID))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, DT.Space.s3)
                .padding(.vertical, DT.Space.s2)
                .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(vm.color(row.categoryID)))
                .padding(.horizontal, -DT.Space.s2)
                .padding(.vertical, DT.Space.s2)
                .contentShape(Rectangle())
        } else {
            HStack(spacing: DT.Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.timeText)
                    if !row.event.isAllDay {
                        Text(vm.builder.endTimeText(row.event))
                    }
                }
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
                .frame(minWidth: DT.Size.touch, alignment: .leading)
                RoundedRectangle(cornerRadius: 3)
                    .fill(vm.color(row.categoryID))
                    .frame(width: Theme.Grid.square, height: Theme.Grid.square)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .dFont(DT.TypeScale.body)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if row.event.hasLocation, let location = row.event.location {
                        Text(location)
                            .dFont(DT.TypeScale.footnote)
                            .foregroundStyle(Theme.sub)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DT.Space.s2)
            .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

extension DetailRow {
    var isBand: Bool {
        if case .band = kind { return true }
        return false
    }
}
