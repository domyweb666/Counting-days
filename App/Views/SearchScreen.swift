import SwiftUI
import CalendarCore

/// 用標題或地點找行程，點一筆就跳到那一天
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [CalEvent] = []

    private var vm: CalendarViewModel { app.vm }

    private var hasQuery: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DT.Space.s4) {
                    if !hasQuery {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "找行程",
                            message: "輸入標題或地點，會從前一年找到後兩年。點一筆就跳到那一天。"
                        )
                    } else if results.isEmpty {
                        EmptyStateView(
                            systemImage: "calendar.badge.exclamationmark",
                            title: "找不到符合的行程",
                            message: "換個關鍵字試試。搜尋範圍是前一年到後兩年。"
                        )
                    } else {
                        SectionCard {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, event in
                                if index > 0 { Hairline() }
                                Button {
                                    vm.show(event.start)
                                    dismiss()
                                } label: {
                                    row(event)
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, DT.Size.screenMargin)
                .padding(.top, DT.Space.s2)
                .padding(.bottom, DT.Space.s8)
            }
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "標題或地點")
            .onChange(of: text) { _, new in
                results = app.store.search(new, today: vm.today, calendar: vm.calendar, hidden: app.settings.value.hiddenCalendarIDs)
            }
            .navigationTitle("搜尋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }

    private func row(_ event: CalEvent) -> some View {
        let year = vm.calendar.component(.year, from: event.start)
        let isPast = event.end < vm.today
        let categoryID = Classifier.categoryID(for: event, settings: app.settings.value)
        return HStack(spacing: DT.Space.s3) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isPast ? Theme.tertiary : vm.color(categoryID))
                .frame(width: Theme.Grid.square, height: Theme.Grid.square)
            VStack(alignment: .leading, spacing: DT.Space.s1) {
                Text(subtitle(event, year: year))
                    .dFont(DT.TypeScale.footnote)
                    .foregroundStyle(Theme.sub)
                Text(event.title)
                    .dFont(DT.TypeScale.body)
                    .foregroundStyle(isPast ? Theme.sub : Theme.ink)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DT.Space.s3)
        .frame(minHeight: DT.Size.row)
        .contentShape(Rectangle())
    }

    private func subtitle(_ event: CalEvent, year: Int) -> String {
        var parts = ["\(year)/\(vm.md(event.start)) 週\(vm.dow(event.start))", vm.builder.timeText(event)]
        if event.hasLocation, let loc = event.location { parts.append(loc) }
        return parts.joined(separator: " · ")
    }
}
