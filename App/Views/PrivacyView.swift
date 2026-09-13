import SwiftUI

struct PrivacyView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your mail stays yours.", systemImage: "lock.shield").font(.title2.bold())
            Text(
                "Transorma reads message contents only to identify supported marketing and find unsubscribe actions. It does not store message bodies or subjects. Classification runs on your Mac."
            )
            Text(
                "Unsubscribe requests contact the sender’s website using the link in the message. That link can identify your email address. DNS lookups use your Mac’s configured resolver. Transorma does not use your browser cookies or login sessions."
            )
            Text(
                "Pending requests store a sender address and unsubscribe link in the app’s protected shared storage. Links are deleted after processing. Activity, pending work, and request fingerprints used to prevent duplicates expire after seven days and are removed when Transorma next runs. There are no analytics, advertising, or developer-operated servers."
            )
            Text(
                "Private Cloud Compute is optional and off by default. If enabled in an entitled build, limited text from an unsubscribe page and action labels may be sent to Apple. Email addresses and URLs are redacted from that text; other personal information on the page may remain."
            )
            Text(
                "Pause protection at any time to stop new work and cancel pending requests. Requests already sent cannot be recalled. Clear completed activity from the Activity tab."
            )
            Divider()
            Text("What Transorma can handle").font(.headline)
            Text(
                "Verified English-language promotions with standard one-click unsubscribe, plus supported links and simple confirmation forms. Messages without a verifiable signature or with unclear intent stay in Mail. Pages requiring login, JavaScript, CAPTCHA, or ambiguous preference changes may remain unresolved."
            )
            Text(
                "Apple Mail controls delivery and Trash retention. The extension cannot scan your existing inbox or guarantee that a sender honors an unsubscribe request."
            )
            Link(
                "About Apple’s Private Cloud Compute",
                destination: URL(string: "https://security.apple.com/private-cloud-compute/")!)
        }.font(.body).lineSpacing(4)
    }

}
