import Foundation
import NexusCore

/// One text in a conversation. Texts sent from the Mac start as `.sending` until the phone answers.
struct SmsMessage: Identifiable, Equatable {
    enum State: Equatable { case received, sending, sent, failed(String) }

    let id: String
    let threadId: String
    let body: String
    let date: Int64
    let outgoing: Bool
    var state: State
}

/// How conversations and times are written.
enum SmsFormat {
    static func title(for thread: SmsThread) -> String {
        if let name = thread.name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return formatted(thread.address)
    }

    /// +5511999990000 → "+55 11 99999-0000"; anything else (short codes, names) stays as it is.
    static func formatted(_ address: String) -> String {
        let digits = address.filter(\.isNumber)
        guard address.hasPrefix("+55"), digits.count == 13 || digits.count == 12 else { return address }
        let area = digits.dropFirst(2).prefix(2), local = digits.dropFirst(4)
        let split = local.index(local.startIndex, offsetBy: local.count - 4)
        return "+55 \(area) \(local[..<split])-\(local[split...])"
    }

    static func initials(for thread: SmsThread) -> String {
        if let name = thread.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        let address = thread.address
        if address.allSatisfy({ $0.isNumber || "+ ()-".contains($0) }) { return "#" }
        return address.first.map { String($0).uppercased() } ?? "#"
    }

    static func shortTime(_ millis: Int64, now: Date = .now, calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let format = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(format.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        return date.formatted(format.day(.twoDigits).month(.twoDigits))
    }

    /// Same rule the phone applies: a real number or short code can be answered, a name like "NUBANK" cannot.
    static func canReply(to address: String) -> Bool {
        guard address.count >= 3, address.count <= 32, address.allSatisfy({ $0.isNumber || "+ ()-".contains($0) }) else { return false }
        return (3...15).contains(address.filter(\.isNumber).count)
    }
}

/// SMS conversations and messages of the connected phone. Nothing is stored on disk; it lives for the session.
@MainActor
final class SmsModel: ObservableObject {
    static let maxText = 1000

    @Published private(set) var threads: [SmsThread] = []
    @Published private(set) var byThread: [String: [SmsMessage]] = [:]
    @Published private(set) var selectedID: String?
    @Published private(set) var loadingThreads = false
    @Published private(set) var loadingMessages = false
    @Published private(set) var moreThreads = false
    @Published private(set) var error: String?

    /// Sends a request to the phone.
    var send: ((Message) -> Void)?

    private var threadsRequest: String?
    private var messageRequests: [String: String] = [:]
    private var sends: [String: (thread: String, message: String)] = [:]
    private var addresses: [String: String] = [:]

    var unreadTotal: Int { threads.reduce(0) { $0 + $1.unread } }

    func messages(of thread: String) -> [SmsMessage] {
        (byThread[thread] ?? []).sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    func setAddress(_ address: String, for thread: String) { addresses[thread] = address }
    func canReply(to thread: String) -> Bool { addresses[thread].map(SmsFormat.canReply(to:)) ?? false }

    func reset() {
        threads = []
        byThread = [:]
        selectedID = nil
        loadingThreads = false
        loadingMessages = false
        moreThreads = false
        error = nil
        threadsRequest = nil
        messageRequests = [:]
        sends = [:]
        addresses = [:]
    }

    // MARK: Requests

    func refresh() {
        let id = Wire.id()
        threadsRequest = id
        loadingThreads = true
        error = nil
        var message = Message("smsThreadsRequest")
        message.id = id
        message.offset = 0
        send?(message)
    }

    func open(_ thread: String) {
        selectedID = thread
        if let index = threads.firstIndex(where: { $0.id == thread }) { threads[index].unread = 0 }
        let id = Wire.id()
        messageRequests[id] = thread
        loadingMessages = true
        var message = Message("smsMessagesRequest")
        message.id = id
        message.threadId = thread
        message.offset = 0
        send?(message)
    }

    func close() { selectedID = nil }

    /// Sends [text] in a conversation. False when there is nothing valid to send.
    @discardableResult
    func sendText(_ text: String, to thread: String) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= Self.maxText, let address = addresses[thread], SmsFormat.canReply(to: address) else { return false }
        let id = Wire.id()
        // Strictly after what is already shown, so two quick sends keep their order.
        let now = Int64(Date.now.timeIntervalSince1970 * 1000)
        let date = max(now, (byThread[thread]?.map(\.date).max() ?? 0) + 1)
        let local = SmsMessage(id: "local-" + id, threadId: thread, body: body, date: date, outgoing: true, state: .sending)
        byThread[thread, default: []].append(local)
        sends[id] = (thread, local.id)
        var message = Message("smsSend")
        message.id = id
        message.address = address
        message.text = body
        send?(message)
        return true
    }

    // MARK: Answers

    func receive(_ message: Message) {
        switch message.type {
        case "smsThreads":
            guard let id = message.id, id == threadsRequest else { return }
            threadsRequest = nil
            loadingThreads = false
            moreThreads = message.more == true
            threads = (message.smsThreads ?? []).sorted { $0.date > $1.date }
            for thread in threads { addresses[thread.id] = thread.address }
        case "smsMessages":
            guard let id = message.id, let thread = messageRequests.removeValue(forKey: id), message.threadId == thread else { return }
            loadingMessages = false
            merge(message.smsEntries ?? [], into: thread)
        case "smsReceived":
            for entry in message.smsEntries ?? [] { received(entry) }
        case "smsSendStatus":
            guard let id = message.id, let target = sends.removeValue(forKey: id) else { return }
            setState(message.enabled == true ? .sent : .failed(message.message ?? "Não foi possível enviar."), of: target.message, in: target.thread)
        case "smsStatus":
            error = message.message
            loadingThreads = false
            loadingMessages = false
        default: break
        }
    }

    private func setState(_ state: SmsMessage.State, of id: String, in thread: String) {
        guard let index = byThread[thread]?.firstIndex(where: { $0.id == id }) else { return }
        byThread[thread]?[index].state = state
    }

    private func merge(_ entries: [SmsEntry], into thread: String) {
        var current = byThread[thread] ?? []
        var known = Set(current.map(\.id))
        for entry in entries where known.insert(entry.id).inserted {
            current.append(SmsMessage(id: entry.id, threadId: thread, body: entry.body, date: entry.date, outgoing: entry.outgoing,
                                      state: entry.outgoing ? .sent : .received))
        }
        // When the phone's own SMS app stores what the Mac sent, drop the Mac's local copy so it shows once.
        let fromPhone = current.filter { !$0.id.hasPrefix("local-") && $0.outgoing }
        current.removeAll { local in
            local.id.hasPrefix("local-") && local.state == .sent
                && fromPhone.contains { $0.body == local.body && abs($0.date - local.date) < 120_000 }
        }
        byThread[thread] = current
    }

    private func received(_ entry: SmsEntry) {
        let isNew = !(byThread[entry.threadId] ?? []).contains { $0.id == entry.id }
        merge([entry], into: entry.threadId)
        addresses[entry.threadId] = entry.address
        let viewing = selectedID == entry.threadId
        if let index = threads.firstIndex(where: { $0.id == entry.threadId }) {
            threads[index].snippet = entry.body
            threads[index].date = max(threads[index].date, entry.date)
            if isNew {
                threads[index].count += 1
                if !entry.outgoing && !viewing { threads[index].unread += 1 }
            }
        } else {
            threads.append(SmsThread(id: entry.threadId, address: entry.address, name: nil, snippet: entry.body, date: entry.date,
                                     unread: entry.outgoing || viewing ? 0 : 1, count: 1))
        }
        threads.sort { $0.date > $1.date }
    }
}
