import SwiftUI

struct ManualLogDatePicker: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    var latestDate: Date?
    @Environment(\.calendar) private var calendar

    var body: some View {
        Group {
            if let latestDate {
                DatePicker(title, selection: $date, in: ...latestDate, displayedComponents: .date)
            } else {
                DatePicker(title, selection: $date, displayedComponents: .date)
            }
        }
        .datePickerStyle(.compact)

        HStack {
            Button("Previous day", systemImage: "chevron.backward") { move(by: -1) }
            Spacer()
            Button("Next day", systemImage: "chevron.forward") { move(by: 1) }
                .disabled(latestDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false)
        }
        .buttonStyle(.borderless)
    }

    private func move(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return }
        date = latestDate.map { min(next, $0) } ?? next
    }
}
