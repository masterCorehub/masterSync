import Foundation
import Network

/// Rules for finding a phone's ADB again after its network address changed.
enum ADBAddress {
    /// The saved `IP:port` pointed at [host] instead; nil when there is nothing to change or either side is unusable.
    nonisolated static func rebased(_ saved: String?, onto host: String?) -> String? {
        guard let saved, let endpoint = ADBEndpoint(saved), let port = port(of: endpoint.address),
              !endpoint.address.hasPrefix("["),
              let host, IPv4Address(host) != nil else { return nil }
        let current = String(endpoint.address.dropLast(String(port).count + 1))
        return current == host ? nil : "\(host):\(port)"
    }

    nonisolated static func port(of address: String?) -> Int? {
        guard let address, let separator = address.lastIndex(of: ":") else { return nil }
        return UInt16(address[address.index(after: separator)...]).flatMap { $0 > 0 ? Int($0) : nil }
    }

    /// Serials of phones on a cable that the Mac is allowed to use: state "device", and not a network address.
    nonisolated static func usbSerials(from devicesOutput: String) -> [String] {
        devicesOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[1] == "device", !fields[0].contains(":") else { return nil }
            return String(fields[0])
        }
    }
}

/// What to do after the Wi-Fi ADB connection to a known phone failed [failures] times in a row.
enum ADBRecovery {
    enum Step: Equatable {
        case retry(status: String)
        case repairOverUSB(status: String)
        case waitForCable(status: String)
    }

    nonisolated static func next(failures: Int, usbDeviceAttached: Bool) -> Step {
        if failures < 2 { return .retry(status: "Procurando o celular nesta rede…") }
        if usbDeviceAttached { return .repairOverUSB(status: "Reativando o ADB do celular pelo cabo…") }
        return .waitForCable(status: "Não achei o ADB do celular nesta rede. Conecte o cabo uma vez: o Mac reativa sozinho.")
    }
}

extension ADBClipboardSession {
    /// `adb tcpip` arguments, or nil when the serial or port could not be what a phone and ADB use.
    nonisolated static func tcpipArguments(serial: String, port: Int) -> [String]? {
        guard !serial.isEmpty, serial.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }),
              (1024...65535).contains(port) else { return nil }
        return ["-s", serial, "tcpip", String(port)]
    }
}
