import Foundation

public enum LibraryDateGrouping: String, CaseIterable {
    case day
    case month
    case none

    public func sections<Item>(
        for items: [Item],
        oldestFirst: Bool = false,
        calendar: Calendar = .current,
        date: (Item) -> Date?
    ) -> [LibraryDateSection<Item>] {
        guard !items.isEmpty else { return [] }
        guard self != .none else { return [LibraryDateSection(date: nil, items: items)] }

        // Calendar boundaries respect the reader's time zone, including daylight saving.
        let grouped = Dictionary(grouping: items) { item -> Date? in
            guard let value = date(item) else { return nil }
            switch self {
            case .day: return calendar.startOfDay(for: value)
            case .month: return calendar.dateInterval(of: .month, for: value)?.start
            case .none: return nil
            }
        }
        let known = grouped.keys.compactMap { $0 }.sorted { oldestFirst ? $0 < $1 : $0 > $1 }
        var sections = known.map { LibraryDateSection(date: $0, items: grouped[$0] ?? []) }
        if let undated = grouped[nil] { sections.append(LibraryDateSection(date: nil, items: undated)) }
        return sections
    }
}

public struct LibraryDateSection<Item>: Identifiable {
    public let date: Date?
    public let items: [Item]
    public var id: Date? { date }
}
