import Foundation
import Testing
@testable import TransormaCore

@Test(arguments: ["127.0.0.1", "10.0.0.1", "169.254.169.254", "172.16.0.1", "192.168.1.1", "100.64.0.1", "0.0.0.0", "192.0.2.1", "198.18.0.1", "224.0.0.1", "255.255.255.255", "::1", "::ffff:127.0.0.1", "fc00::1", "fe80::1", "2001:db8::1", "2002:7f00:1::", "3fff::1"])
func blocksNonPublicAddresses(address: String) { #expect(!URLPolicy.isPublicAddress(address)) }

@Test(arguments: ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111", "2001:4860:4860::8888"])
func acceptsPublicAddresses(address: String) { #expect(URLPolicy.isPublicAddress(address)) }

@Test(arguments: ["http://store.example.com/u", "https://user:pass@store.example.com/u", "https://store.example.com:8443/u", "https://127.0.0.1/u", "https://2130706433/u", "https://printer.local/u", "https://store.example.com/u#fragment"])
func rejectsUnsafeURLs(value: String) throws {
    let url = try #require(URL(string: value))
    #expect(throws: (any Error).self) { try URLPolicy.validate(url) }
}

@Test func oneClickWireRequestHasNoAmbientCredentials() throws {
    let url = try #require(URL(string: "https://store.example.com/u?t=abc"))
    let bytes = try PublicHTTPSClient.encode(HTTPRequest(url: url, method: "POST", body: Data("List-Unsubscribe=One-Click".utf8)))
    let wire = String(decoding: bytes, as: UTF8.self)
    #expect(wire.contains("POST /u?t=abc HTTP/1.1\r\n"))
    #expect(wire.contains("Content-Length: 26\r\n"))
    #expect(!wire.contains("Cookie:"))
    #expect(!wire.contains("Authorization:"))
    #expect(!wire.contains("Referer:"))
}

@Test func decodesChunkedResponsesAndRejectsAmbiguousFraming() throws {
    let response = try HTTPDecoder.decode(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n0\r\n\r\n".utf8))
    #expect(String(decoding: response.body, as: UTF8.self) == "Hello")
    #expect(throws: (any Error).self) {
        try HTTPDecoder.decode(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n5\r\nHello\r\n0\r\n\r\n".utf8))
    }
}
