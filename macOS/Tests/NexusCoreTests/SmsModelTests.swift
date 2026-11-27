import NexusCore
@testable import NexusMasterSync
import XCTest

@MainActor
final class SmsModelTests: XCTestCase {
    private func thread(_ id: String, address: String = "+5511999990000", name: String? = nil, snippet: String = "oi", date: Int64 = 1000,
                        unread: Int = 0, count: Int = 1) -> SmsThread {
        SmsThread(id: id, address: address, name: name, snippet: snippet, date: date, unread: unread, count: count)
    }

    private func entry(_ id: String, thread: String = "1", body: String = "oi", date: Int64, outgoing: Bool = false,
                       address: String = "+5511999990000") -> SmsEntry {
        SmsEntry(id: id, threadId: thread, address: address, body: body, date: date, outgoing: outgoing)
    }

    private func message(_ type: String, id: String? = nil, build: (inout Message) -> Void = { _ in }) -> Message {
        var message = Message(type)
        message.id = id
        build(&message)
        return message
    }

    private func make() -> (SmsModel, () -> [Message]) {
        let model = SmsModel()
        var sent: [Message] = []
        model.send = { sent.append($0) }
        return (model, { sent })
    }

    // MARK: Conversations

    func testRefreshAsksForTheConversations() {
        let (model, sent) = make()
        model.refresh()
        XCTAssertEqual(sent().last?.type, "smsThreadsRequest")
        XCTAssertTrue(model.loadingThreads)
    }

    func testThreadsAnswerFillsTheListNewestFirst() throws {
        let (model, sent) = make()
        model.refresh()
        let id = try XCTUnwrap(sent().last?.id)
        model.receive(message("smsThreads", id: id) { $0.smsThreads = [thread("1", date: 100), thread("2", date: 300)]; $0.more = false })
        XCTAssertEqual(model.threads.map(\.id), ["2", "1"])
        XCTAssertFalse(model.loadingThreads)
    }

    func testAnAnswerToAnOldRequestIsIgnored() {
        let (model, _) = make()
        model.refresh()
        model.receive(message("smsThreads", id: Wire.id()) { $0.smsThreads = [thread("9")] })
        XCTAssertTrue(model.threads.isEmpty)
    }

    func testUnreadCountAddsUpAndOpeningAThreadClearsIt() throws {
        let (model, sent) = make()
        model.refresh()
        model.receive(message("smsThreads", id: try XCTUnwrap(sent().last?.id)) {
            $0.smsThreads = [thread("1", unread: 2), thread("2", unread: 1)] })
        XCTAssertEqual(model.unreadTotal, 3)
        model.open("1")
        XCTAssertEqual(model.unreadTotal, 1)
    }

    // MARK: Messages

    func testOpeningAThreadAsksForItsMessages() throws {
        let (model, sent) = make()
        model.open("7")
        XCTAssertEqual(sent().last?.type, "smsMessagesRequest")
        XCTAssertEqual(sent().last?.threadId, "7")
        XCTAssertEqual(model.selectedID, "7")
    }

    func testMessagesAreShownOldestFirstWithoutDuplicates() throws {
        let (model, sent) = make()
        model.open("1")
        let id = try XCTUnwrap(sent().last?.id)
        model.receive(message("smsMessages", id: id) { $0.threadId = "1"; $0.smsEntries = [entry("3", date: 300), entry("2", date: 200)] })
        model.receive(message("smsReceived") { $0.smsEntries = [entry("3", date: 300), entry("4", date: 400)] })
        XCTAssertEqual(model.messages(of: "1").map(\.id), ["2", "3", "4"])
    }

    func testAMessageForAnotherThreadDoesNotLandInTheOpenOne() throws {
        let (model, sent) = make()
        model.open("1")
        model.receive(message("smsMessages", id: try XCTUnwrap(sent().last?.id)) { $0.threadId = "2"; $0.smsEntries = [entry("9", thread: "2", date: 1)] })
        XCTAssertTrue(model.messages(of: "1").isEmpty)
    }

    func testAnIncomingTextRaisesUnreadAndUpdatesTheThread() throws {
        let (model, sent) = make()
        model.refresh()
        model.receive(message("smsThreads", id: try XCTUnwrap(sent().last?.id)) { $0.smsThreads = [thread("1", snippet: "velho", date: 100)] })
        model.receive(message("smsReceived") { $0.smsEntries = [entry("5", body: "chegou", date: 500)] })
        XCTAssertEqual(model.threads.first?.snippet, "chegou")
        XCTAssertEqual(model.threads.first?.unread, 1)
        XCTAssertEqual(model.unreadTotal, 1)
    }

    func testAnIncomingTextInTheOpenThreadDoesNotCountAsUnread() throws {
        let (model, sent) = make()
        model.refresh()
        model.receive(message("smsThreads", id: try XCTUnwrap(sent().last?.id)) { $0.smsThreads = [thread("1")] })
        model.open("1")
        model.receive(message("smsReceived") { $0.smsEntries = [entry("5", date: 500)] })
        XCTAssertEqual(model.unreadTotal, 0)
    }

    func testATextFromAnUnknownThreadCreatesIt() {
        let (model, _) = make()
        model.receive(message("smsReceived") { $0.smsEntries = [entry("5", thread: "42", body: "novo", date: 500, address: "29104")] })
        XCTAssertEqual(model.threads.map(\.id), ["42"])
        XCTAssertEqual(model.threads.first?.address, "29104")
        XCTAssertEqual(model.threads.first?.unread, 1)
    }

    // MARK: Sending

    func testSendingAddsAPendingMessageAndAsksThePhone() throws {
        let (model, sent) = make()
        model.open("1")
        model.setAddress("+5511999990000", for: "1")
        XCTAssertTrue(model.sendText("  olá  ", to: "1"))
        let request = try XCTUnwrap(sent().last)
        XCTAssertEqual(request.type, "smsSend")
        XCTAssertEqual(request.address, "+5511999990000")
        XCTAssertEqual(request.text, "olá")
        let shown = model.messages(of: "1").last
        XCTAssertEqual(shown?.body, "olá")
        XCTAssertEqual(shown?.outgoing, true)
        XCTAssertEqual(shown?.state, .sending)
    }

    func testTheStatusAnswerMarksTheMessageSentOrFailed() throws {
        let (model, sent) = make()
        model.setAddress("+5511999990000", for: "1")
        _ = model.sendText("a", to: "1")
        let first = try XCTUnwrap(sent().last?.id)
        model.receive(message("smsSendStatus", id: first) { $0.enabled = true; $0.message = "SMS enviado." })
        XCTAssertEqual(model.messages(of: "1").last?.state, .sent)

        _ = model.sendText("b", to: "1")
        let second = try XCTUnwrap(sent().last?.id)
        model.receive(message("smsSendStatus", id: second) { $0.enabled = false; $0.message = "O Android não conseguiu enviar o SMS." })
        XCTAssertEqual(model.messages(of: "1").last?.state, .failed("O Android não conseguiu enviar o SMS."))
    }

    func testEmptyOrTooLongTextIsNotSent() {
        let (model, sent) = make()
        model.setAddress("+5511999990000", for: "1")
        XCTAssertFalse(model.sendText("   ", to: "1"))
        XCTAssertFalse(model.sendText(String(repeating: "x", count: 1001), to: "1"))
        XCTAssertTrue(sent().isEmpty)
    }

    func testNamesLikeBanksCannotBeAnswered() {
        let (model, sent) = make()
        model.setAddress("NUBANK", for: "1")
        XCTAssertFalse(model.canReply(to: "1"))
        XCTAssertFalse(model.sendText("oi", to: "1"))
        XCTAssertTrue(sent().isEmpty)
        model.setAddress("29104", for: "2")
        XCTAssertTrue(model.canReply(to: "2"))
    }

    func testAStatusMessageFromThePhoneShowsAsAnError() {
        let (model, _) = make()
        model.receive(message("smsStatus", id: nil) { $0.message = "Autorize a leitura de SMS no MasterSync do Android." })
        XCTAssertEqual(model.error, "Autorize a leitura de SMS no MasterSync do Android.")
    }

    func testResetClearsEverythingWhenThePhoneChanges() throws {
        let (model, sent) = make()
        model.refresh()
        model.receive(message("smsThreads", id: try XCTUnwrap(sent().last?.id)) { $0.smsThreads = [thread("1", unread: 2)] })
        model.reset()
        XCTAssertTrue(model.threads.isEmpty)
        XCTAssertEqual(model.unreadTotal, 0)
        XCTAssertNil(model.selectedID)
    }

    // MARK: Text

    func testDisplayNameUsesTheContactThenTheFormattedNumber() {
        XCTAssertEqual(SmsFormat.title(for: thread("1", address: "+5511999990000", name: "Mãe")), "Mãe")
        XCTAssertEqual(SmsFormat.title(for: thread("1", address: "+5511999990000")), "+55 11 99999-0000")
        XCTAssertEqual(SmsFormat.title(for: thread("1", address: "NUBANK")), "NUBANK")
        XCTAssertEqual(SmsFormat.title(for: thread("1", address: "29104")), "29104")
    }

    func testInitials() {
        XCTAssertEqual(SmsFormat.initials(for: thread("1", name: "Lucas Andrade")), "LA")
        XCTAssertEqual(SmsFormat.initials(for: thread("1", name: "Mãe")), "M")
        XCTAssertEqual(SmsFormat.initials(for: thread("1", address: "29104")), "#")
        XCTAssertEqual(SmsFormat.initials(for: thread("1", address: "NUBANK")), "N")
    }

    func testTimeLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 15, minute: 0))!
        func stamp(_ days: Int, hour: Int = 9, minute: Int = 5) -> Int64 {
            let day = calendar.date(byAdding: .day, value: -days, to: now)!
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        XCTAssertEqual(SmsFormat.shortTime(stamp(0), now: now, calendar: calendar), "09:05")
        XCTAssertEqual(SmsFormat.shortTime(stamp(1), now: now, calendar: calendar), "Ontem")
        XCTAssertEqual(SmsFormat.shortTime(stamp(10), now: now, calendar: calendar), "17/11")
    }
}
