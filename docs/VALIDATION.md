# Validation record — September 13, 2026

Environment: Apple silicon, macOS 27.0 RC (26A428), Swift 6.4 (swiftlang-6.4.0.34.1), Command Line Tools macOS 27 SDK. Installed Xcode IDE: 26.6 (17F113).

Completed locally:

- Core Swift package builds in Swift 6 language mode with application-extension API restrictions.
- 23 Swift Testing tests pass, including parameterized RSA/Ed25519 signatures, published RFC 8463 interoperability vectors, tampering, malformed mail, MIME transfer decoding, public-IP filtering, HTTP framing, duplicate prevention, consent/keep-list enforcement, interrupted jobs, one-click handling, static-form navigation, and rejection of invented model actions.
- Read-only live system DNS lookup and public-IP-pinned TLS request to `https://example.com/` succeed (HTTP 200).
- Native on-device Foundation Models inference passes three synthetic classifications: promotion, mixed receipt with advertising, and an instruction-injected security alert. It also selects the expected action from a synthetic unsubscribe form. No live unsubscribe URL is requested by these diagnostics.
- The MailKit adapter passes Swift 6 type checking with `-application-extension` against the macOS 27 SDK.
- The SwiftUI companion app compiles and links with the native compiler into a local preview. The preview launches with a fresh temporary store and no unsubscribe worker. An image of the app's own window is rendered and inspected at `.build/Preview/Transorma.png`.
- Project, entitlement, and privacy property lists validate; shell scripts pass syntax checking; `git diff --check` passes.

Not established:

- A complete Xcode 27 build/archive, App Store validation, or UI automation run. The Xcode 26.6 build service rejects the macOS 27 SDK during Info.plist processing. The available command-line compiler can verify and link sources but does not substitute for a release archive.
- Installed, signed MailKit callback behavior, real mailbox actions, sustained arrival loads, or extension lifecycle/inference timing. No mailbox was accessed or modified.
- Production classification accuracy. The synthetic checks are tiny smoke tests; they are not held-out accuracy measurements.
- PCC inference. The account has neither paid developer nor Small Business enrollment, and the executable has no approved PCC entitlement. The public macOS 27 calls compile, but that path has not run.

Reproduce with the commands in [README.md](../README.md). Follow [release preparation](RELEASE.md) before enabling the extension on a primary mailbox or publishing it.
