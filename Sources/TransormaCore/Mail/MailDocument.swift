import Foundation

/// Parses RFC 5322 messages, restoring uniformly LF-delimited local mail to CRLF for DKIM and MIME.
/// All other octets are preserved; mixed or broken line endings are rejected.
public struct MailDocument: Sendable {
    public struct Header: Sendable {
        public let name: String
        public let raw: Data
        public var value: String {
            let line = String(decoding: raw, as: UTF8.self)
            return String(
                line.dropFirst((line.firstIndex(of: ":").map { line.distance(from: line.startIndex, to: $0) } ?? 0) + 1)
            )
            .replacingOccurrences(of: "\r\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        }
    }

    public let headers: [Header]
    public let body: Data

    public init(raw: Data) throws {
        let raw = try Self.networkData(raw)
        guard let boundary = raw.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound <= 64_000
        else {
            throw MailError.malformedMessage
        }
        let head = raw[..<boundary.lowerBound]
        let lines = Self.splitLines(Data(head))
        var parsed: [Header] = []
        for line in lines {
            if line.first == 32 || line.first == 9 {
                guard let previous = parsed.popLast() else { throw MailError.malformedMessage }
                parsed.append(Header(name: previous.name, raw: previous.raw + Data("\r\n".utf8) + line))
            } else {
                guard let colon = line.firstIndex(of: 58), colon > line.startIndex else {
                    throw MailError.malformedMessage
                }
                let nameBytes = line[..<colon]
                guard nameBytes.allSatisfy({ (33...126).contains($0) && $0 != 58 }),
                    !line.contains(10), !line.contains(13)
                else { throw MailError.malformedMessage }
                parsed.append(Header(name: String(decoding: nameBytes, as: UTF8.self).lowercased(), raw: line))
            }
        }
        guard parsed.count <= 250 else { throw MailError.malformedMessage }
        headers = parsed
        body = Data(raw[boundary.upperBound...])
    }

    private static func networkData(_ raw: Data) throws -> Data {
        guard raw.count <= 2_000_000 else { throw MailError.malformedMessage }
        if raw.contains(13) {
            var previous: UInt8?
            for byte in raw {
                guard byte != 10 || previous == 13, previous != 13 || byte == 10 else {
                    throw MailError.malformedMessage
                }
                previous = byte
            }
            guard previous != 13 else { throw MailError.malformedMessage }
            return raw
        }

        // Mail's local source can use LF. RFC 6376 §3.4 assumes network CRLF before canonicalization.
        // Work on bytes: decoding and re-encoding a String could corrupt signed non-UTF-8 content.
        let size = raw.count + raw.count { $0 == 10 }
        guard size <= 2_000_000 else { throw MailError.malformedMessage }
        var result = Data(capacity: size)
        for byte in raw {
            if byte == 10 { result.append(13) }
            result.append(byte)
        }
        return result
    }

    public func values(_ name: String) -> [String] { headers.filter { $0.name == name.lowercased() }.map(\.value) }
    public func single(_ name: String) -> String? {
        let values = values(name)
        return values.count == 1 ? values[0] : nil
    }

    public static func splitLines(_ data: Data) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        while let end = data.range(of: Data([13, 10]), in: start..<data.endIndex) {
            result.append(Data(data[start..<end.lowerBound]))
            start = end.upperBound
        }
        result.append(Data(data[start...]))
        return result
    }

    /// Only an unambiguous single mailbox is accepted for automated actions.
    public var sender: String? {
        guard let from = single("from") else { return nil }
        let candidate: String
        if let open = from.firstIndex(of: "<"), let close = from.firstIndex(of: ">"), open < close {
            guard from[close...].dropFirst().trimmingCharacters(in: .whitespaces).isEmpty,
                !from[..<open].contains(",")
            else { return nil }
            candidate = String(from[from.index(after: open)..<close])
        } else {
            candidate = from
        }
        guard
            candidate.range(
                of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"#,
                options: .regularExpression) != nil
        else { return nil }
        return candidate.lowercased()
    }

    public var oneClickURL: URL? {
        guard single("list-unsubscribe-post") == "List-Unsubscribe=One-Click",
            let field = single("list-unsubscribe")
        else { return nil }
        let urls = Self.headerURLs(field).filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard urls.count == 1, urls[0].scheme?.lowercased() == "https" else { return nil }
        return urls[0]
    }

    public static func headerURLs(_ field: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: "<([^<>\\s]+)>") else { return [] }
        let ns = field as NSString
        return regex.matches(in: field, range: NSRange(location: 0, length: ns.length)).compactMap {
            URL(string: ns.substring(with: $0.range(at: 1)))
        }
    }

    public var content: MessageContent { MIMEParser.extract(headers: self, depth: 0) }
}

public struct MessageContent: Sendable {
    public var text = ""
    public var html = ""
    public init(text: String = "", html: String = "") {
        self.text = text
        self.html = html
    }
}

enum MIMEParser {
    static func extract(headers message: MailDocument, depth: Int) -> MessageContent {
        guard depth < 6 else { return MessageContent() }
        let contentType = message.single("content-type") ?? "text/plain; charset=us-ascii"
        guard !(message.single("content-disposition") ?? "").lowercased().hasPrefix("attachment") else {
            return MessageContent()
        }
        if contentType.lowercased().hasPrefix("multipart/") {
            guard let boundary = parameter("boundary", in: contentType), boundary.utf8.count <= 200 else {
                return MessageContent()
            }
            var parts: [Data] = []
            var current: Data?
            for line in MailDocument.splitLines(message.body) {
                if line == Data(("--" + boundary).utf8) || line == Data(("--" + boundary + "--").utf8) {
                    if let current { parts.append(current) }
                    if line == Data(("--" + boundary + "--").utf8) {
                        current = nil
                        break
                    }
                    current = Data()
                } else if current != nil {
                    current?.append(line + Data([13, 10]))
                }
                if parts.count >= 30 { break }
            }
            return parts.compactMap { try? MailDocument(raw: $0) }.reduce(into: MessageContent()) { output, part in
                let content = extract(headers: part, depth: depth + 1)
                output.text = String((output.text + "\n" + content.text).prefix(24_000))
                output.html = String((output.html + "\n" + content.html).prefix(120_000))
            }
        }
        let type = contentType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard type == "text/plain" || type == "text/html" else { return MessageContent() }
        let decoded: Data
        switch message.single("content-transfer-encoding")?.lowercased() {
        case "base64":
            guard let data = Data(base64Encoded: message.body, options: .ignoreUnknownCharacters) else {
                return MessageContent()
            }
            decoded = data
        case "quoted-printable": decoded = quotedPrintable(message.body)
        case nil, "7bit", "8bit", "binary": decoded = message.body
        default: return MessageContent()
        }
        let charset = (parameter("charset", in: contentType) ?? "utf-8").lowercased()
        let encoding: String.Encoding =
            switch charset {
            case "iso-8859-1", "latin1": .isoLatin1
            case "windows-1252": .windowsCP1252
            default: .utf8
            }
        guard let text = String(data: decoded, encoding: encoding) else { return MessageContent() }
        return type == "text/html"
            ? MessageContent(html: String(text.prefix(120_000))) : MessageContent(text: String(text.prefix(24_000)))
    }

    static func parameter(_ name: String, in value: String) -> String? {
        let pattern = "(?:^|;)\\s*" + name + "\\s*=\\s*(?:\"([^\"]*)\"|([^;\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
        return (value as NSString).substring(with: range)
    }

    static func quotedPrintable(_ data: Data) -> Data {
        let bytes = Array(data)
        var output = Data()
        var i = 0
        while i < bytes.count {
            if bytes[i] == 61, i + 2 < bytes.count {
                if bytes[i + 1] == 13, bytes[i + 2] == 10 {
                    i += 3
                    continue
                }
                if let byte = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                    output.append(byte)
                    i += 3
                    continue
                }
            }
            output.append(bytes[i])
            i += 1
        }
        return output
    }
}

enum HeaderText {
    static func decode(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let ns = text as NSString
            let charset = ns.substring(with: match.range(at: 1)).lowercased()
            let mode = ns.substring(with: match.range(at: 2)).lowercased()
            let raw = ns.substring(with: match.range(at: 3))
            let data =
                mode == "b"
                ? Data(base64Encoded: raw)
                : MIMEParser.quotedPrintable(Data(raw.replacingOccurrences(of: "_", with: " ").utf8))
            let encoding: String.Encoding = charset == "iso-8859-1" ? .isoLatin1 : .utf8
            if let data, let decoded = String(data: data, encoding: encoding),
                let range = Range(match.range, in: result)
            {
                result.replaceSubrange(range, with: decoded)
            }
        }
        return result
    }
}
