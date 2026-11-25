import Foundation
import XCTest
@testable import NexusCore

final class LibraryDateGroupingTests: XCTestCase {
    func testDayGroupsUseTheLocalCalendarAndPreserveItemOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -10_800))
        let iso = ISO8601DateFormatter()
        let beforeMidnight = try XCTUnwrap(iso.date(from: "2026-11-24T02:59:00Z"))
        let afterMidnight = try XCTUnwrap(iso.date(from: "2026-11-24T03:00:00Z"))
        let afterMidnightAgain = afterMidnight.addingTimeInterval(90)
        let items = [afterMidnightAgain, afterMidnight, beforeMidnight]

        let groups = LibraryDateGrouping.day.sections(for: items, calendar: calendar) { $0 }

        XCTAssertEqual(groups.map(\.date), [afterMidnight, calendar.startOfDay(for: beforeMidnight)])
        XCTAssertEqual(groups.map(\.items), [[afterMidnightAgain, afterMidnight], [beforeMidnight]])
    }

    func testMonthGroupsSortOldestFirstAndKeepUndatedItemsAtTheEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let iso = ISO8601DateFormatter()
        let october = try XCTUnwrap(iso.date(from: "2026-10-01T00:00:00Z"))
        let november = try XCTUnwrap(iso.date(from: "2026-11-01T00:00:00Z"))
        let items = [november, nil, october]

        let grouped = LibraryDateGrouping.month.sections(for: items, oldestFirst: true, calendar: calendar) { $0 }
        let flat = LibraryDateGrouping.none.sections(for: items, calendar: calendar) { $0 }

        XCTAssertEqual(grouped.map(\.date), [october, november, nil])
        XCTAssertEqual(grouped.map(\.items), [[october], [november], [nil]])
        XCTAssertEqual(flat.map(\.items), [items])
    }
}
