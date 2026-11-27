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

    func testFaintTextMeetsContrastOnWindowInBothSchemes() {
        for scheme in schemes {
            let palette = NexusPalette(scheme: scheme)
            XCTAssertGreaterThanOrEqual(NexusPalette.contrast(palette.faint, palette.canvas), 4.5, "faint \(scheme)")
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

final class StableHueTests: XCTestCase {
    func testHueIsStableAndInRange() {
        XCTAssertEqual(NexusPalette.stableHue("com.whatsapp/.Home"), NexusPalette.stableHue("com.whatsapp/.Home"))
        for id in ["a", "com.example.app1/.Main", ""] {
            let hue = NexusPalette.stableHue(id)
            XCTAssertTrue((0..<360).contains(hue), id)
        }
    }

    func testSimilarIdsGetDifferentColors() {
        let hues = (0..<8).map { NexusPalette.stableHue("com.example.app\($0)/.Main") }
        // Buckets of 30°: near-identical package names must not all land on the same color.
        XCTAssertGreaterThanOrEqual(Set(hues.map { Int($0 / 30) }).count, 5, "\(hues)")
    }
}
