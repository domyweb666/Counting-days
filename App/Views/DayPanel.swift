import SwiftUI
import CalendarCore

/// 點一天展開的時間表。四種呈現方式共用這一個。
struct DayPanel: View {
    let vm: CalendarViewModel
    let day: DayModel
    let actions: CalendarActions

    var body: some View {
        let rows = vm.builder.detailRows(for: day)
        VStack(alignment: .leading, spacing: DT.Space.s1) {
            header(count: rows.count)
            if rows.isEmpty {
                Text("這天沒有行程")
                    .dFont(DT.TypeScale.subheadline)
                    .foregroundStyle(Theme.sub)
                    .padding(.vertical, DT.Space.s2)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0, !row.isSolid, !rows[index - 1].isSolid {
                    Hairline()
                }
                Button {
                    actions.open(row.event)
                } label: {
                    DetailRowView(vm: vm, row: row, isPast: day.isPast)
                }
                .buttonStyle(PressStyle())
                .contextMenu { menu(for: row) }
            }
            WideButton(title: "新增行程", kind: .secondary, systemImage: "plus") {
                actions.add(day.date)
            }
            .padding(.top, DT.Space.s2)
        }
        .padding(.top, DT.Space.s3)
        .padding(.horizontal, DT.Space.s4)
        .padding(.bottom, DT.Space.s4)
        .background(RoundedRectangle(cornerRadius: DT.Radius.xl).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.xl).strokeBorder(Theme.accent, lineWidth: 2))
        .padding(.horizontal, DT.Space.s1)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DT.Space.s2) {
                    Text("\(vm.md(day.date)) 週\(vm.dow(day.date))")
                        .dFont(DT.TypeScale.title3)
                        .foregroundStyle(Theme.ink)
                    if count > 0 {
                        Text("\(count) 件").dFont(DT.TypeScale.footnote).foregroundStyle(Theme.sub)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .dFont(DT.TypeScale.caption)
                        .foregroundStyle(day.holidays.isEmpty ? Theme.sub : Theme.destructive)
                }
            }
            Spacer()
            Button {
                vm.toggle(day.date)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: DT.Size.iconButton, height: DT.Size.iconButton)
                    .background(Circle().fill(Theme.muted))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("收合")
        }
        .padding(.bottom, DT.Space.s1)
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

extension DetailRow {
    /// 跨日事件與主事件畫成整條實色
    var isSolid: Bool {
        switch kind {
        case .band, .head: return true
        case .normal, .routine: return false
        }
    }
}

struct DetailRowView: View {
    let vm: CalendarViewModel
    let row: DetailRow
    let isPast: Bool

    private var title: String {
        if case .band(let n, _) = row.kind { return "\(row.title) · 第 \(n) 天" }
        return row.title
    }

    var body: some View {
        if row.isSolid { solid } else { plain }
    }

    private var solid: some View {
        let fg = isPast ? Theme.sub : vm.onColor(row.categoryID)
        return HStack(spacing: DT.Space.s3) {
            Text(row.timeText)
                .dFont(DT.TypeScale.footnote)
                .opacity(0.85)
                .frame(minWidth: DT.Size.touch, alignment: .leading)
            Text(title)
                .dFont(DT.TypeScale.title3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityLabel("已置頂")
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, DT.Space.s3)
        .padding(.vertical, DT.Space.s2)
        .frame(maxWidth: .infinity, minHeight: DT.Size.row, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DT.Radius.md).fill(isPast ? Theme.muted : vm.color(row.categoryID)))
        .padding(.horizontal, -DT.Space.s2)
        .padding(.bottom, DT.Space.s1)
        .contentShape(Rectangle())
    }

    private var plain: some View {
        let dim = isPast || row.kind == .routine
        return HStack(spacing: DT.Space.s3) {
            Text(row.timeText)
                .dFont(DT.TypeScale.footnote)
                .foregroundStyle(Theme.sub)
                .frame(minWidth: DT.Size.touch, alignment: .leading)
            RoundedRectangle(cornerRadius: 3)
                .fill(isPast ? Theme.tertiary : vm.color(row.categoryID))
                .frame(width: Theme.Grid.square, height: Theme.Grid.square)
            Text(title)
                .dFont(DT.TypeScale.body)
                .foregroundStyle(dim ? Theme.sub : Theme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.sub)
                    .accessibilityLabel("已置頂")
            }
        }
        .padding(.vertical, DT.Space.s1)
        .frame(maxWidth: .infinity, minHeight: DT.Size.touch, alignment: .leading)
        .contentShape(Rectangle())
    }
}
