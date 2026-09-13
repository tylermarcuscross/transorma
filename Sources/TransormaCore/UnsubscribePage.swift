import CMailSystem
import Foundation

public struct PageAction: Sendable {
    public let id: Int
    public let label: String
    public let request: HTTPRequest
}

public struct UnsubscribePage: Sendable {
    public let text: String
    public let actions: [PageAction]
    public let confirmsUnsubscribe: Bool
    public let blocked: Bool

    public init(html: String, baseURL: URL) throws {
        guard html.utf8.count <= 300_000 else { throw MailError.oversizedResponse }
        let parsed = try HTMLDocument(html)
        text = String(parsed.visibleText.prefix(8000))
        let lower = text.lowercased()
        confirmsUnsubscribe = [
            "you have been unsubscribed", "you are now unsubscribed", "you've been unsubscribed",
            "successfully unsubscribed", "unsubscribe successful", "removed from our mailing list",
        ].contains { lower.contains($0) }
        blocked =
            ["captcha", "sign in to", "log in to", "enter your password", "verify your identity"].contains {
                lower.contains($0)
            }
            || parsed.elements("input").contains { parsed.attribute($0, "type")?.lowercased() == "password" }
            || parsed.elements("iframe").contains {
                (parsed.attribute($0, "src") ?? "").lowercased().contains("captcha")
            }
        guard !blocked else {
            actions = []
            return
        }
        var candidates: [(String, HTTPRequest)] = []
        for node in parsed.elements("a").prefix(100) {
            let label = parsed.text(node)
            guard Self.isUnsubscribeLabel(label), let href = parsed.attribute(node, "href"),
                let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                (try? URLPolicy.validate(url, sameHost: baseURL.host)) != nil
            else { continue }
            candidates.append((label, HTTPRequest(url: url)))
        }
        for form in parsed.elements("form").prefix(10) {
            guard let action = parsed.attribute(form, "action"),
                let url = URL(string: action, relativeTo: baseURL)?.absoluteURL,
                (try? URLPolicy.validate(url, sameHost: baseURL.host)) != nil,
                (parsed.attribute(form, "method") ?? "get").lowercased() == "post",
                [nil, "application/x-www-form-urlencoded"].contains(parsed.attribute(form, "enctype")?.lowercased())
            else { continue }
            let controls = parsed.descendants(form).filter {
                ["input", "button", "select", "textarea"].contains(parsed.name($0))
            }
            guard controls.count <= 30 else { continue }
            var fields: [(String, String)] = []
            var buttons: [(String, String?, String)] = []
            var unsafe = false
            for control in controls {
                if parsed.attribute(control, "disabled") != nil { continue }
                let name = parsed.attribute(control, "name")
                let value = parsed.attribute(control, "value") ?? ""
                let type = (parsed.attribute(control, "type") ?? (parsed.name(control) == "button" ? "submit" : "text"))
                    .lowercased()
                if type == "hidden", parsed.name(control) == "input", let name, name.utf8.count < 256,
                    value.utf8.count < 8192
                {
                    fields.append((name, value))
                } else if type == "submit" {
                    let label = parsed.name(control) == "button" ? parsed.text(control) : value
                    buttons.append((label, name, value))
                } else {
                    unsafe = true
                }
            }
            // No invented form values, checkboxes, preferences changes, or ambiguous submit controls.
            guard !unsafe, buttons.count == 1, let button = buttons.first, Self.isUnsubscribeLabel(button.0) else {
                continue
            }
            if let name = button.1 { fields.append((name, button.2)) }
            let encoded = fields.map { Self.formEncode($0.0) + "=" + Self.formEncode($0.1) }.joined(separator: "&")
            guard encoded.utf8.count <= 32_000 else { continue }
            candidates.append((button.0, HTTPRequest(url: url, method: "POST", body: Data(encoded.utf8))))
        }
        actions = candidates.prefix(12).enumerated().map {
            PageAction(id: $0.offset, label: String($0.element.0.prefix(200)), request: $0.element.1)
        }
    }

    public static func isUnsubscribeLabel(_ label: String) -> Bool {
        let lower = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count <= 200,
            ![
                "resubscribe", "do not", "don't", "cancel", "delete", "account", "paid", "purchase", "billing",
                "payment", "keep receiving", "stay subscribed",
            ].contains(where: lower.contains)
        else { return false }
        return ["unsubscribe", "opt out", "opt-out", "stop receiving", "remove me"].contains(where: lower.contains)
    }

    static func formEncode(_ text: String) -> String {
        text.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }

    public static func emailLinks(in html: String) -> [URL] {
        guard let parsed = try? HTMLDocument(html) else { return [] }
        return parsed.elements("a").prefix(300).compactMap { node in
            guard isUnsubscribeLabel(parsed.text(node)), let href = parsed.attribute(node, "href"),
                let url = URL(string: href), (try? URLPolicy.validate(url)) != nil
            else { return nil }
            return url
        }
    }

    public static func visibleText(in html: String) -> String { (try? HTMLDocument(html).visibleText) ?? "" }
}

/// libxml2 performs recovery parsing with network access disabled. No scripts or resources are loaded.
private final class HTMLDocument {
    private let document: htmlDocPtr
    init(_ html: String) throws {
        guard html.utf8.count <= 300_000 else { throw MailError.oversizedResponse }
        let options = Int32(
            HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue
                | HTML_PARSE_NOWARNING.rawValue)
        guard let document = html.withCString({ htmlReadMemory($0, Int32(html.utf8.count), nil, "UTF-8", options) })
        else { throw MailError.unsupportedPage }
        self.document = document
    }
    deinit { xmlFreeDoc(document) }
    var visibleText: String { text(xmlDocGetRootElement(document)) }
    func name(_ node: xmlNodePtr) -> String { node.pointee.name.map { String(cString: $0) } ?? "" }
    func attribute(_ node: xmlNodePtr, _ name: String) -> String? {
        guard let value = xmlGetProp(node, name) else { return nil }
        defer { transorma_xml_free(value) }
        return String(cString: value)
    }
    func text(_ root: xmlNodePtr?) -> String {
        guard let root else { return "" }
        var pieces: [String] = []
        var remaining = 24_000
        func walk(_ node: xmlNodePtr, depth: Int) {
            guard depth < 60, remaining > 0 else { return }
            if ["script", "style", "noscript", "template", "head"].contains(name(node)) { return }
            if node.pointee.type == XML_TEXT_NODE, let content = node.pointee.content {
                let value = String(String(cString: content).prefix(remaining))
                pieces.append(value)
                remaining -= value.count
            }
            var child = node.pointee.children
            while let node = child {
                walk(node, depth: depth + 1)
                child = node.pointee.next
            }
        }
        walk(root, depth: 0)
        return pieces.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func elements(_ tag: String) -> [xmlNodePtr] {
        guard let root = xmlDocGetRootElement(document) else { return [] }
        return ([root] + descendants(root)).filter { name($0) == tag }
    }
    func descendants(_ root: xmlNodePtr) -> [xmlNodePtr] {
        var result: [xmlNodePtr] = []
        func walk(_ parent: xmlNodePtr, depth: Int) {
            guard depth < 60, result.count < 10_000 else { return }
            var child = parent.pointee.children
            while let node = child, result.count < 10_000 {
                result.append(node)
                walk(node, depth: depth + 1)
                child = node.pointee.next
            }
        }
        walk(root, depth: 0)
        return result
    }
}
