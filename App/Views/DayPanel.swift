import SwiftUI
import CalendarCore

/// 點一天展開的時間表。四種呈現方式共用這一個。
struct DayPanel: View {
    let vm: CalendarViewModel
    let day: DayModel
    let actions: CalendarActions

    var body: some View {
        let rows = vm.builder.detailRows(for: day)
        VStack(alignment: .leading, spacing: 6) {
            header(count: rows.count)
            if rows.isEmpty {
                Text("這天沒有行程")
                    .sFont(15, .medium)
                    .foregroundStyle(Theme.pastFg)
                    .padding(.horizontal, 6)
            }
            ForEach(rows) { row in
                Button {
                    actions.open(row.event)
                } label: {
                    DetailRowView(vm: vm, row: row, isPast: day.isPast)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: row) }
            }
            Button {
                actions.add(day.date)
            } label: {
                Label("新增行程", systemImage: "plus")
                    .sFont(15, .bold)
                    .foregroundStyle(Theme.select)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.select, lineWidth: 2))
        .padding(.horizontal, 4)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(vm.md(day.date)) 週\(vm.dow(day.date))")
                        .sFont(19, .heavy)
                        .foregroundStyle(Theme.ink)
                    if count > 0 {
                        Text("\(count) 件").sFont(13, .bold).foregroundStyle(Theme.pastFg)
                    }
                }
                Text(subtitle)
                    .sFont(12, .medium)
                    .foregroundStyle(day.holidays.isEmpty ? Theme.sub : Theme.holiday)
            }
            Spacer()
            Button {
                vm.toggle(day.date)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.bg))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收合")
        }
        .padding(.leading, 4)
    }

    private var subtitle: String {
        var parts = day.holidays
        if vm.settings.value.showLunar { parts.append(vm.lunarFullText(day.date)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func menu(for row: DetailRow) -> some View {
        let id = row.event.seriesID
        let s = vm.settings.value
        if case .band = row.kind {
            EmptyView()
        } else if row.kind != .routine {
            Button(s.pinned.contains(id) ? "取消置頂" : "置頂為當天主事件", systemImage: "pin") {
                vm.settings.togglePin(id)
            }
            Button("設定短名", systemImage: "textformat.size.smaller") {
                actions.shortName(row.event)
            }
        }
        Button(s.countdowns.contains(id) ? "移出倒數日" : "加入倒數日", systemImage: "hourglass") {
            vm.settings.toggleCountdown(id)
        }
        Button("編輯", systemImage: "pencil") {
            actions.open(row.event)
        }
    }
}

struct DetailRowView: View {
    let vm: CalendarViewModel
    let row: DetailRow
    let isPast: Bool

    private var isSolid: Bool {
        switch row.kind {
        case .band, .head: return true
        case .normal, .routine: return false
        }
    }

    private var title: String {
        if case .band(let n, _) = row.kind { return "\(row.title) · 第 \(n) 天" }
        return row.title
    }

    var body: some View {
        let color = vm.color(row.categoryID)
        let solidFg: Color = isPast ? Theme.pastFg : .white
        HStack(spacing: 8) {
            Text(row.timeText)
                .sFont(13, .bold)
                .foregroundStyle(isSolid ? solidFg : Theme.pastFg)
                .frame(minWidth: 42, alignment: .leading)
            RoundedRectangle(cornerRadius: 3)
                .fill(isSolid ? solidFg : (isPast ? Theme.sub : color))
                .frame(width: 10, height: 10)
            Text(title)
                .sFont(isSolid ? 19 : 15, isSolid ? .heavy : (row.kind == .routine ? .medium : .bold))
                .foregroundStyle(isSolid ? solidFg : (isPast || row.kind == .routine ? Theme.pastFg : Theme.ink))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSolid ? solidFg : Theme.sub)
                    .accessibilityLabel("已置頂")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: isSolid ? 44 : 34, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSolid ? (isPast ? Theme.pastBg : color) : Color.clear))
        .contentShape(Rectangle())
    }
}
