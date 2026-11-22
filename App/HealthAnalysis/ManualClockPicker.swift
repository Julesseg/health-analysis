import HealthAnalysisCore
import SwiftUI

struct ManualClockPicker: View {
    let label: Text
    @Binding var time: ManualClockTime
    @Environment(\.calendar) private var calendar

    var body: some View {
        var pickerCalendar = calendar
        pickerCalendar.timeZone = .gmt
        return DatePicker(selection: Binding(
            get: { time.pickerDate },
            set: { time = ManualClockTime(pickerDate: $0) }
        ), displayedComponents: .hourAndMinute) {
            label
        }
        .datePickerStyle(.compact)
        .environment(\.calendar, pickerCalendar)
        .environment(\.timeZone, .gmt)
        .accessibilityIdentifier("manual-clock-picker")
    }
}

extension ManualClockTime {
    var pickerDate: Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3_600 + minute * 60))
    }

    init(pickerDate: Date) {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: pickerDate)
        self.init(hour: components.hour!, minute: components.minute!)
    }
}
