import AppKit
@testable import NexusMasterSync
import SwiftUI
import XCTest

final class NexusPaletteTests: XCTestCase {
    private let schemes: [ColorScheme] = [.dark, .light]

    func testInkAndMutedMeetContrastOnWindowInBothSchemes() {
        for scheme in schemes {
            let palette = NexusPalette(scheme: scheme)
            XCTAssertGreaterThanOrEqual(NexusPalette.contrast(palette.ink, palette.canvas), 4.5, "ink \(scheme)")
            XCTAssertGreaterThanOrEqual(NexusPalette.contrast(palette.muted, palette.canvas), 4.5, "muted \(scheme)")
        }
    }

    func testAccentTextMeetsContrastOnWindowInBothSchemes() {
        for scheme in schemes {
            let palette = NexusPalette(scheme: scheme)
            XCTAssertGreaterThanOrEqual(NexusPalette.contrast(palette.accent, palette.canvas), 4.5, "accent \(scheme)")
        }
    }

    func testInkOnFillMeetsContrastInBothSchemes() {
        for scheme in schemes {
            let palette = NexusPalette(scheme: scheme)
            XCTAssertGreaterThanOrEqual(NexusPalette.contrast(palette.accentInk, palette.fill), 4.5, "fill \(scheme)")
        }
    }

    func testTokensDifferBetweenSchemes() {
        let dark = NexusPalette(scheme: .dark), light = NexusPalette(scheme: .light)
        XCTAssertNotEqual(NexusPalette.rgba(dark.panel), NexusPalette.rgba(light.panel))
        XCTAssertNotEqual(NexusPalette.rgba(dark.line), NexusPalette.rgba(light.line))
        XCTAssertNotEqual(NexusPalette.rgba(dark.active), NexusPalette.rgba(light.active))
    }

    func testFillIsTheSameTealInBothSchemes() {
        XCTAssertEqual(NexusPalette.rgba(NexusPalette(scheme: .dark).fill), NexusPalette.rgba(NexusPalette(scheme: .light).fill))
    }
}
