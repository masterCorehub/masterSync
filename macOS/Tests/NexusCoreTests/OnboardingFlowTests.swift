import AppKit
@testable import NexusMasterSync
import SwiftUI
import XCTest

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testStepsRunWelcomeConnectFeatures() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .connect, .features])
        XCTAssertEqual(OnboardingStep.welcome.next, .connect)
        XCTAssertEqual(OnboardingStep.connect.next, .features)
        XCTAssertNil(OnboardingStep.features.next)
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.features.previous, .connect)
        XCTAssertTrue(OnboardingStep.features.isLast)
        XCTAssertFalse(OnboardingStep.connect.isLast)
    }

    func testPositionLabel() {
        XCTAssertEqual(OnboardingStep.welcome.position, "1 de 3")
        XCTAssertEqual(OnboardingStep.features.position, "3 de 3")
    }

    func testAutoShowOnlyOnFirstRunWithoutNetworkOrPeers() {
        XCTAssertTrue(OnboardingFlow.shouldAutoShow(seen: false, networkConsent: false, hasPeers: false))
        XCTAssertFalse(OnboardingFlow.shouldAutoShow(seen: true, networkConsent: false, hasPeers: false))
        XCTAssertFalse(OnboardingFlow.shouldAutoShow(seen: false, networkConsent: true, hasPeers: false))
        XCTAssertFalse(OnboardingFlow.shouldAutoShow(seen: false, networkConsent: false, hasPeers: true))
    }

    func testWelcomeListsTheMainFeatures() {
        XCTAssertGreaterThanOrEqual(OnboardingFlow.highlights.count, 5)
        XCTAssertTrue(OnboardingFlow.highlights.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.icon.isEmpty })
    }

    func testStepsRenderInBothSchemes() throws {
        let model = NexusModel()
        let shell = ShellRenderTests()
        for scheme in [ColorScheme.dark, .light] {
            for step in OnboardingStep.allCases {
                let view: AnyView = switch step {
                case .welcome: AnyView(OnboardingWelcomeStep(onStart: {}, onSkip: {}))
                case .features: AnyView(OnboardingFeaturesStep(model: model, onFinish: {}))
                case .connect: AnyView(OnboardingHeader(step: .connect))
                }
                _ = try shell.render(view, name: "onboarding-\(step)", scheme: scheme, width: 520, height: 560)
            }
        }
    }
}
