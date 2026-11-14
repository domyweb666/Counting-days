import SwiftUI
import CalendarCore

/// 用標題或地點找行程，點一筆就跳到那一天
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [CalEvent] = []

    private var vm: CalendarViewModel { app.vm }

    var body: some View {
        NavigationStack {
            List {
                if !text.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                    Text("找不到符合的行程（搜尋範圍是前一年到後兩年）")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { event in
                    Button {
                        vm.jump(to: event.start)
                        dismiss()
                    } label: {
                        row(event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
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
    }

    private func row(_ event: CalEvent) -> some View {
        let year = vm.calendar.component(.year, from: event.start)
        let isPast = event.end < vm.today
        let categoryID = Classifier.categoryID(for: event, settings: app.settings.value)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isPast ? Theme.sub : vm.color(categoryID))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .sFont(16, .bold)
                    .foregroundStyle(isPast ? Theme.pastFg : Theme.ink)
                Text(subtitle(event, year: year))
                    .sFont(13, .medium)
                    .foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func subtitle(_ event: CalEvent, year: Int) -> String {
        var parts = ["\(year)/\(vm.md(event.start)) 週\(vm.dow(event.start))", vm.builder.timeText(event)]
        if event.hasLocation, let loc = event.location { parts.append(loc) }
        return parts.joined(separator: " · ")
    }
}
