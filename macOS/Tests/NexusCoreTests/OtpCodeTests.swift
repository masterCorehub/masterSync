@testable import NexusMasterSync
import XCTest

final class OtpCodeTests: XCTestCase {
    func testFindsCodesInTypicalMessages() {
        XCTAssertEqual(OtpCode.find(in: "Seu código de verificação é 482 913. Não compartilhe."), "482913")
        XCTAssertEqual(OtpCode.find(in: "G-123456 é o seu código de verificação do Google"), "123456")
        XCTAssertEqual(OtpCode.find(in: "Código: 4821"), "4821")
        XCTAssertEqual(OtpCode.find(in: "Your verification code is 123456"), "123456")
        XCTAssertEqual(OtpCode.find(in: "Use 98765432 como senha de acesso"), "98765432")
        XCTAssertEqual(OtpCode.find(in: "Token de segurança 482-913 válido por 5 minutos"), "482913")
        XCTAssertEqual(OtpCode.find(in: "Nubank: confirmação de login, código 7391"), "7391")
    }

    func testIgnoresTextWithoutAVerificationWord() {
        XCTAssertNil(OtpCode.find(in: "Seu pedido 12345678 saiu para entrega"))
        XCTAssertNil(OtpCode.find(in: "Compra de R$ 1234 aprovada em Padaria Central"))
        XCTAssertNil(OtpCode.find(in: "Rafa: bora às 1930 no futebol?"))
        XCTAssertNil(OtpCode.find(in: ""))
    }

    func testIgnoresNumbersThatAreNotCodes() {
        XCTAssertNil(OtpCode.find(in: "Código de rastreio 12"), "curto demais")
        XCTAssertNil(OtpCode.find(in: "Código de barras 123456789012"), "longo demais")
        XCTAssertNil(OtpCode.find(in: "Senha alterada em 12:34"), "hora")
        XCTAssertNil(OtpCode.find(in: "Código promocional: 50% de desconto"))
    }

    func testPrefersTheNumberAfterTheKeyword() {
        XCTAssertEqual(OtpCode.find(in: "Pedido 99887766. Código de verificação: 4455"), "4455")
    }

    func testMoneyIsNotACode() {
        XCTAssertNil(OtpCode.find(in: "Código de confirmação enviado. Valor R$ 12345"))
    }

    func testDisplayGroupsLongCodes() {
        XCTAssertEqual(OtpCode.display("482913"), "482 913")
        XCTAssertEqual(OtpCode.display("12345678"), "1234 5678")
        XCTAssertEqual(OtpCode.display("4821"), "4821")
        XCTAssertEqual(OtpCode.display("12345"), "12345")
    }

    func testAnAcceptedCodeIsDigitsOfSensibleLength() {
        XCTAssertTrue(OtpCode.isValid("482913"))
        XCTAssertFalse(OtpCode.isValid("123"))
        XCTAssertFalse(OtpCode.isValid("123456789"))
        XCTAssertFalse(OtpCode.isValid("12ab34"))
        XCTAssertFalse(OtpCode.isValid(""))
    }

    func testRecentNoticesOnly() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(OtpCode.isFresh(now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(OtpCode.isFresh(now.addingTimeInterval(-600), now: now))
        XCTAssertTrue(OtpCode.isFresh(nil, now: now))
    }

    func testTheSameNoticeIsOnlyHandledOnce() {
        var tracker = OtpCode.Tracker()
        XCTAssertTrue(tracker.shouldHandle(id: "p.1", code: "482913"))
        XCTAssertFalse(tracker.shouldHandle(id: "p.1", code: "482913"))
        XCTAssertTrue(tracker.shouldHandle(id: "p.1", code: "111222"), "outro código na mesma notificação")
        XCTAssertTrue(tracker.shouldHandle(id: "p.2", code: "482913"))
    }

    func testTrackerForgetsOldEntriesToStayBounded() {
        var tracker = OtpCode.Tracker(limit: 3)
        for index in 0..<10 { _ = tracker.shouldHandle(id: "p.\(index)", code: "123456") }
        XCTAssertLessThanOrEqual(tracker.count, 3)
    }
}
