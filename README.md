# Transorma

Automatic unsubscribe and marketing cleanup for Apple Mail on macOS 27.

The app is under development. Local builds and automated tests work without paid developer enrollment; signed Mail integration and App Store validation remain release work. See the [validation record](Docs/VALIDATION.md) and [release preparation](Docs/RELEASE.md).

## Start developing

Install Xcode 27 or newer and open this folder in VS Code, or open `Transorma.xcodeproj` in Xcode and select the **Transorma** scheme. For VS Code, install the recommended official Swift extension and the development-only Xcode adapter:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
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

## Running against Mail

After developer enrollment, configure the app and extension for the same provisioned App Group, `group.me.tylercross.transorma`. Use a signed **Debug** build; Development cannot process mail. Enable Transorma in **Mail → Settings → Extensions**, allow message-content access, then enable **Activate Transorma** in the app. See [signed installation](Docs/RELEASE.md#signed-installation).

Add your approved developer account in Xcode → Settings → Accounts and confirm the team in `Config/Shared.xcconfig`. Run `make build-signed` (or VS Code's **Transorma: build signed app** task) to build the Mail-enabled app with automatic provisioning. The output is `.build/Xcode/Build/Products/Debug/Transorma.app`; install that copy in Applications. `make run` continues to open a clearly labeled preview with disposable settings, even if its activation switch is on.

Mail must be running to supply messages. When you reopen Mail, Transorma checks the messages Mail downloads, including those that arrived while it was closed. The regular app defaults to opening at login to finish queued unsubscribes after the extension exits; its window can stay closed. You can turn login launch off in Settings, and later launches respect that choice. Development builds leave login registration disabled. One-time protection setup authorizes automatic unsubscribe requests and Trash actions. Messages can be recovered from Mail's Trash; resubscription happens on the sender's website.

For troubleshooting, **Settings → Diagnostics** shows extension startup, callbacks, and recent decisions. Use `make logs` for live system logs, `make logs-show` for retained logs, and `make diagnose` for installed state. The [development guide](Docs/DEVELOPMENT.md#diagnosing-incoming-mail) covers Console, crash reports, and read-only `.eml` assessment.

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
