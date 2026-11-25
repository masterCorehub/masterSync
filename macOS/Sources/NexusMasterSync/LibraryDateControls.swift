import NexusCore
import SwiftUI

struct LibraryDatePicker: View {
    @Binding var selection: LibraryDateGrouping

    var body: some View {
        Picker("Agrupar por", selection: $selection) {
            Text("Dia").tag(LibraryDateGrouping.day)
            Text("Mês").tag(LibraryDateGrouping.month)
            Text("Nenhum").tag(LibraryDateGrouping.none)
        }.fixedSize()
    }
}

struct LibraryDateHeading: View {
    let date: Date?
    let grouping: LibraryDateGrouping
    @Environment(\.colorScheme) private var scheme
    @Environment(\.calendar) private var calendar

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(NexusPalette(scheme: scheme).ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        guard let date else { return "Sem data" }
        let locale = Locale(identifier: "pt_BR")
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if grouping == .month {
            let month = date.formatted(format.month(.wide).year())
            return String(month.prefix(1)).uppercased(with: locale) + month.dropFirst()
        }
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        return date.formatted(format.day().month(.wide).year())
    }
}
