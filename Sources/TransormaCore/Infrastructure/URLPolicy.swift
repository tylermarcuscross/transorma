import Darwin
import Foundation

public enum URLPolicy {
    public static func validate(_ url: URL, sameHost: String? = nil) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
            host.utf8.count <= 253, url.absoluteString.utf8.count <= 8192,
            url.user == nil, url.password == nil, url.fragment == nil,
            url.port == nil || url.port == 443,
            host.contains("."), !host.hasSuffix("."),
            host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
            !["localhost", "local", "internal", "home", "lan", "test", "invalid", "example", "onion"].contains(
                host.split(separator: ".").last.map(String.init) ?? ""),
            sameHost == nil || host == sameHost?.lowercased()
        else { throw MailError.unsafeURL }
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) != 1, !host.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw MailError.unsafeURL
        }
    }

    public static func isPublicAddress(_ address: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            let n = UInt32(bigEndian: v4.s_addr)
            let blocked: [(UInt32, UInt32)] = [
                (0x0000_0000, 0xff00_0000), (0x0a00_0000, 0xff00_0000), (0x6440_0000, 0xffc0_0000),
                (0x7f00_0000, 0xff00_0000), (0xa9fe_0000, 0xffff_0000), (0xac10_0000, 0xfff0_0000),
                (0xc000_0000, 0xffff_ff00), (0xc000_0200, 0xffff_ff00), (0xc058_6300, 0xffff_ff00),
                (0xc0a8_0000, 0xffff_0000), (0xc612_0000, 0xfffe_0000), (0xc633_6400, 0xffff_ff00),
                (0xcb00_7100, 0xffff_ff00), (0xe000_0000, 0xe000_0000),
            ]
            return !blocked.contains { n & $0.1 == $0.0 }
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, address, &v6) == 1 else { return false }
        return withUnsafeBytes(of: v6) { bytes in
            // Global unicast only; exclude protocol assignments, documentation and 6to4.
            guard bytes[0] & 0xe0 == 0x20 else { return false }
            if bytes[0] == 0x20 && bytes[1] == 0x01 {
                if bytes[2] < 0x02 || (bytes[2] == 0x0d && bytes[3] == 0xb8) { return false }
            }
            if bytes[0] == 0x20 && bytes[1] == 0x02 { return false }
            if bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] < 0x10 { return false }
            return true
        }
    }
}
