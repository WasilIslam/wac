import AppKit

/// Two-line system glance for the drawer footer:
///   load 2.61/10 · 192.168.1.24
///   UK 14:32 · ET 09:32 · PT 06:32
enum SysInfo {
    /// Clock presets selectable in Settings.
    static let clockOptions: [(code: String, tz: String)] = [
        ("UK", "Europe/London"),
        ("ET", "America/New_York"),
        ("CT", "America/Chicago"),
        ("PT", "America/Los_Angeles"),
        ("UTC", "UTC"),
        ("PK", "Asia/Karachi"),
    ]
    static let clocksDefaultsKey = "wac.clocks"

    static func selectedClocks() -> [String] {
        UserDefaults.standard.stringArray(forKey: clocksDefaultsKey) ?? ["UK", "ET"]
    }

    static func summary() -> String {
        var parts: [String] = []

        // Load average vs core count: how many processes want CPU time,
        // out of how many cores can serve them.
        var loads = [Double](repeating: 0, count: 1)
        if getloadavg(&loads, 1) == 1 {
            let cores = ProcessInfo.processInfo.activeProcessorCount
            parts.append(String(format: "load %.2f/%d", loads[0], cores))
        }

        parts.append(localIPv4() ?? "offline")

        var clocks: [String] = []
        let selected = selectedClocks()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        for (code, tz) in clockOptions where selected.contains(code) {
            guard let zone = TimeZone(identifier: tz) else { continue }
            formatter.timeZone = zone
            clocks.append("\(code) \(formatter.string(from: Date()))")
        }

        // Clocks get their own line so they never fight the stats for width
        let statsLine = parts.joined(separator: " · ")
        return clocks.isEmpty ? statsLine : statsLine + "\n" + clocks.joined(separator: " · ")
    }

    private static func localIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return nil }
        defer { freeifaddrs(addrs) }
        var pointer = addrs
        while let current = pointer {
            let ifa = current.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name).hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            pointer = ifa.ifa_next
        }
        return nil
    }
}
