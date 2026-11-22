import SwiftUI

struct ManualLogDatePicker: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    var latestDate: Date?
    var earliestDate: Date?
    @Environment(\.calendar) private var calendar

    var body: some View {
        Group {
            if let earliestDate, let latestDate {
                DatePicker(title, selection: $date, in: earliestDate...latestDate, displayedComponents: .date)
            } else if let earliestDate {
                DatePicker(title, selection: $date, in: earliestDate..., displayedComponents: .date)
            } else if let latestDate {
                DatePicker(title, selection: $date, in: ...latestDate, displayedComponents: .date)
            } else {
                DatePicker(title, selection: $date, displayedComponents: .date)
            }
        }
        .datePickerStyle(.compact)

        HStack {
            Button("Previous day", systemImage: "chevron.backward") { move(by: -1) }
                .disabled(earliestDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false)
            Spacer()
            Button("Next day", systemImage: "chevron.forward") { move(by: 1) }
                .disabled(latestDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false)
        }
        .buttonStyle(.borderless)
    }

    private func move(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return }
        let atOrAfterStart = earliestDate.map { max(next, $0) } ?? next
        date = latestDate.map { min(atOrAfterStart, $0) } ?? atOrAfterStart
    }
}
