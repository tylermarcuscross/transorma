# Transorma

Automatic unsubscribe and marketing cleanup for Apple Mail on macOS 27.

Enable protection once. When Mail receives a supported marketing message, Transorma queues an unsubscribe and asks Mail to move the message to Trash. The companion app shows activity and resumes queued work. There are no per-message approval dialogs.

The app is under development. Local builds and automated tests work without paid developer enrollment; signed Mail integration and App Store validation remain release work. See the [validation record](Docs/VALIDATION.md) and [release preparation](Docs/RELEASE.md).

## Start developing

Install Xcode 27 or newer and open this folder in VS Code, or open `Transorma.xcodeproj` in Xcode and select the **Transorma** scheme. For VS Code, install the recommended official Swift extension and the development-only Xcode adapter:

```sh
brew install xcode-build-server
make doctor
make build
```

In VS Code, **⇧⌘B** builds and **F5 → Transorma: isolated UI** debugs the app. Swift files format on save. In Xcode, use **⌘R**, **⌘U**, and native SwiftUI previews. Both editors use the Development configuration: disposable settings, no unsubscribe worker, and no paid account required.

```sh
make run          # Open the UI preview; does not process email
make test-core    # Independent Swift package tests
make test         # Core, app model, and UI tests through Xcode
make verify       # Formatting, unit tests, app/extension build, whitespace
make format       # Format all Swift sources with the bundled swift-format
```

Run `make` for all commands. The [development guide](Docs/DEVELOPMENT.md) covers toolchain selection, VS Code indexing, debugging, and signed configurations. No remote Swift package dependencies or separate Swift installation are required.

## Code layout

| Location | Responsibility |
| --- | --- |
| `App/` | SwiftUI app, observable app state, views, and resources. |
| `TransormaMailExtension/` | MailKit callbacks and extension resources. |
| `Sources/TransormaCore/` | Mail parsing, protection decisions, unsubscribe workflows, and infrastructure in one shared module. |
| `Sources/CMailSystem/` | Bridge to Apple's system DNS resolver and libxml2. |
| `Sources/TransormaDiagnostics/` | Explicit live network and on-device model smoke checks. |
| `Tests/` | Core, app model, and UI tests with shared deterministic fixtures. |
| `Config/` | Xcode compiler and signing configurations. |
| `Docs/` | Architecture, development, release guidance, and third-party notices. |
| `Makefile`, `Scripts/`, `.vscode/` | Shared commands and editor/toolchain integration. |

Read the [architecture guide](Docs/ARCHITECTURE.md) for the boundaries, processing flow, concurrency rules, and reasons behind this structure.

`Transorma.xcodeproj` defines native targets and packaging. It remains versioned and is hidden from VS Code's Explorer along with generated state; `make xcode` opens it. Build outputs live in ignored `.build/`, and `make clean` removes generated builds and editor indexes. See [workspace conventions](Docs/DEVELOPMENT.md#workspace-and-repository-layout).

## Implemented behavior

- MailKit message actions, App Sandbox, and a shared App Group using public APIs.
- Transactional and personal-mail exclusions, on-device marketing classification, and a conservative English keyword fallback when intelligence is off or unavailable.
- Complete-body DKIM verification, RSA-SHA256 and Ed25519-SHA256, signed decision headers, exact From-domain alignment, and published RFC interoperability tests.
- RFC 8058 one-click HTTPS POST without cookies, credentials, or redirects.
- An Apple Intelligence fallback for an explicit unsubscribe link in authenticated mail. It supports bounded same-host navigation and simple HTML forms. The model chooses from validated actions; application code constructs requests.
- Optional macOS 27 Private Cloud Compute reasoning after local inference, guarded by both user opt-in and the actual signing entitlement. Default entitlements do not enable PCC.
- A persistent bounded queue with exclusive cross-process claims, consent checks before network writes, explicit temporary-error backoff, seven-day expiry, and token removal after completion.
- Automatic catch-up as Mail downloads messages that arrived while it was closed, with bounded assessment waiting for download bursts. Queued unsubscribes resume at Transorma launch, on Mac wake, and when Mail opens.
- Two sections: Settings for protection, Mail setup, intelligence, and login launch; Activity for unsubscribe history and progress. The menu bar offers Open Transorma (⌘N), Settings… (⌘,), and Quit (⌘Q).

## Running against Mail

After developer enrollment, configure the app and extension for the same provisioned App Group, `group.me.tylercross.transorma`. Use a signed **Debug** build; Development cannot process mail. Enable Transorma in **Mail → Settings → Extensions**, allow message-content access, then enable **Activate Transorma** in the app. See [signed installation](Docs/RELEASE.md#signed-installation).

Add your approved developer account in Xcode → Settings → Accounts and confirm the team in `Config/Shared.xcconfig`. Run `make build-signed` (or VS Code's **Transorma: build signed app** task) to build the Mail-enabled app with automatic provisioning. The output is `.build/Xcode/Build/Products/Debug/Transorma.app`; install that copy in Applications. `make run` continues to open a clearly labeled preview with disposable settings, even if its activation switch is on.

Mail must be running to supply messages. When you reopen Mail, Transorma checks the messages Mail downloads, including those that arrived while it was closed. The regular app defaults to opening at login to finish queued unsubscribes after the extension exits; its window can stay closed. You can turn login launch off in Settings, and later launches respect that choice. Development builds leave login registration disabled. One-time protection setup authorizes automatic unsubscribe requests and Trash actions. Messages can be recovered from Mail's Trash; resubscription happens on the sender's website.

## Coverage boundaries

The extension processes messages supplied by MailKit; it cannot enumerate an existing inbox or replay previously downloaded messages that were skipped, timed out, or received while protection was paused. Catch-up depends on Mail downloading the messages, not their unread status. It does not run continuously while the Mac sleeps. An unsubscribe may complete after Trash is requested. If the callback deadline wins before queue commitment, assessment cannot later enqueue work. Bursts that exceed the bounded assessment capacity preserve the excess messages.

Ambiguous, encrypted, malformed, oversized, unsigned, or unsupported messages are preserved. A list header alone does not establish marketing. The conservative rules leave many newsletters untouched; synthetic model checks do not establish production classification accuracy.

Web fallback supports UTF-8 HTML, same-host links, and simple POST forms with hidden fields and an explicit unsubscribe button. It does not automate login, CAPTCHA, JavaScript, cookies, arbitrary preferences, cross-host navigation, or `mailto:` requests. Plain-text-only links without a List-Unsubscribe header are not extracted. Transport interruptions with an unknown outcome are not automatically replayed. A successful response does not prove that future mail will stop.

[Private Cloud Compute access](https://developer.apple.com/private-cloud-compute) requires eligible program membership and an approved managed entitlement. An OS or Xcode upgrade does not grant it. The [release guide](Docs/RELEASE.md) tracks signing, inference evaluation, privacy review, and distribution requirements.

Specifications: [MailKit message actions](https://developer.apple.com/documentation/mailkit/memessageactionhandler), [RFC 8058](https://www.rfc-editor.org/rfc/rfc8058), [RFC 6376](https://www.rfc-editor.org/rfc/rfc6376), [RFC 8463](https://www.rfc-editor.org/rfc/rfc8463). Attribution for published test vectors is in [third-party notices](Docs/THIRD_PARTY_NOTICES.md).
