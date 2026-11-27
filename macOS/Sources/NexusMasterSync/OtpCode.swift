import Foundation

/// Finds a verification code (the number from a login SMS or e-mail) in a notification's text.
/// The Android app uses the same rule, so a code it spots while the phone is locked is the one the Mac would spot.
enum OtpCode {
    private static let keyword = try! NSRegularExpression(
        pattern: "codigo|code|verifica|senha|password|\\bpin\\b|token|otp|autentica|confirma|login|acesso|seguranca")
    private static let candidate = try! NSRegularExpression(
        pattern: "(?<![\\d.,])(\\d{4,8}|\\d{3,4}[ -]\\d{3,4})(?!\\d|%|[.,]\\d)")

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// The digits of the code, without spaces or hyphens, or nil when the text has no verification word or no plausible number.
    static func find(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let source = folded(text) as NSString
        let whole = NSRange(location: 0, length: source.length)
        guard let firstKeyword = keyword.firstMatch(in: source as String, range: whole) else { return nil }
        let matches = candidate.matches(in: source as String, range: whole).filter { match in
            // Amounts are not codes: "R$ 1234", "$ 50".
            let before = source.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
            return !before.hasSuffix("$")
        }
        let pick = matches.first { $0.range.location >= firstKeyword.range.location } ?? matches.first
        return pick.map { source.substring(with: $0.range).filter(\.isNumber) }
    }

    static func isValid(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// 482913 → "482 913": easier to read in the pop-up.
    static func display(_ code: String) -> String {
        guard code.count == 6 || code.count == 8 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return code[..<middle] + " " + code[middle...]
    }

    /// An old notice (the phone was offline, or a refresh re-sent it) must not copy a stale code.
    static func isFresh(_ date: Date?, now: Date = .now) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) <= 180
    }

    /// Remembers which notice and code were already handled, so a refresh of the list never copies twice.
    struct Tracker {
        private var seen: [String] = []
        private let limit: Int

        init(limit: Int = 200) { self.limit = limit }

        var count: Int { seen.count }

        mutating func shouldHandle(id: String, code: String) -> Bool {
            let key = id + "|" + code
            guard !seen.contains(key) else { return false }
            seen.append(key)
            if seen.count > limit { seen.removeFirst(seen.count - limit) }
            return true
        }
    }
}
