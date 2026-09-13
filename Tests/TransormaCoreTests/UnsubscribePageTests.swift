import Foundation
import Testing

@testable import TransormaCore

@Test(
    arguments: ["formaction='/unsubscribe'", "formmethod='get'", "formenctype='text/plain'", "form='another-form'"],
    ["button", "input"])
func submitOverridesCannotSendToTheWrongEndpoint(attribute: String, control: String) throws {
    let url = try #require(URL(string: "https://store.example.com/u"))
    let submit =
        control == "button"
        ? "<button type=submit \(attribute)>Unsubscribe</button>"
        : "<input type=submit value=Unsubscribe \(attribute)>"
    let html = "<form action='/delete-account' method=post><input type=hidden name=token value=secret>\(submit)</form>"
    #expect(try UnsubscribePage(html: html, baseURL: url).actions.isEmpty)
}

@Test func restrictsUnsafeFormControlsAndCrossHostLinks() throws {
    let url = try #require(URL(string: "https://store.example.com/u"))
    for html in [
        "<form method=post action=/u><input type=password name=password><button>Unsubscribe</button></form>",
        "<form method=post action=/u><input name=email><button>Unsubscribe</button></form>",
        "<a href='https://attacker.example.com/u'>Unsubscribe</a>",
        "<button onclick='deleteAccount()'>Unsubscribe</button>",
        "<form method=post action=/u><button>Do not unsubscribe</button></form>",
    ] { #expect(try UnsubscribePage(html: html, baseURL: url).actions.isEmpty) }
}
