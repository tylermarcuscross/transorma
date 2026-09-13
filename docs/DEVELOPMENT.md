# Working on Transorma

Open the **repository folder** in VS Code. The workspace uses Xcode 27's Swift toolchain, the official Swift extension, and one development-only adapter, `xcode-build-server`. The app has no remote package dependencies.

## First setup

1. Install Xcode 27 RC or newer and finish its first launch. This Mac's installation is `/Applications/Xcode-27.app`.
2. Install the recommended **Swift** extension (`swiftlang.swift-vscode`). It supplies completion, diagnostics, formatting, tests, and the Swift debugger integration.
3. Install the Xcode adapter: `brew install xcode-build-server`. It gives the language server the actual compiler arguments for the app, extension, and tests.
4. Run **Tasks: Run Build Task** (`⇧⌘B`). Choose **Developer: Reload Window** once after changing toolchains or opening an existing workspace with stale diagnostics.

The checked-in VS Code settings point to `/Applications/Xcode-27.app`. If you install Xcode elsewhere, update `swift.path` and the two `DEVELOPER_DIR` entries in `.vscode/settings.json`. Project scripts honor an explicit `DEVELOPER_DIR`, then look for a selected Xcode 27+ installation or `/Applications/Xcode-27.app`. They do not require a privileged system-wide `xcode-select` change.

For Xcode itself, open `transorma.xcodeproj` and use the shared **Transorma** scheme. Select the new Xcode in Settings → Locations → Command Line Tools if you also want ordinary terminals outside VS Code to use it.

## Everyday workflow

| Action | VS Code | Terminal |
| --- | --- | --- |
| Build app, extension, diagnostics, and test bundles | `⇧⌘B` | `zsh scripts/build.sh` |
| Debug the companion UI | F5 → **Transorma: isolated UI** | Build, then `open .build/Xcode/Build/Products/Debug/transorma.app --args --ui-testing` |
| Run core tests | **Transorma: test core** task | `zsh scripts/test-core.sh` |
| Run UI tests | **Transorma: test UI** task | `zsh scripts/build.sh test -only-testing:transormaUITests` |
| Run all Xcode tests | | `zsh scripts/build.sh test` |
| Format | Save a Swift file; **Transorma: format** for all files | `zsh scripts/style.sh format` |
| Check style | **Transorma: lint** task | `zsh scripts/style.sh lint` |
| Check before sharing changes | **Transorma: verify** task | `zsh scripts/verify.sh` |

The local build script uses ad hoc signing and omits distribution entitlements **only for that command**. The F5 configuration passes `--ui-testing`: a Debug-only mode with fresh temporary settings and no unsubscribe worker. You can set breakpoints, change views, and toggle protection without touching a mailbox. Temporary settings reset on each launch. Mail registration and shared App Group access require a properly provisioned build; follow [release preparation](RELEASE.md) once enrollment is approved.

The two diagnostics launch configurations remain available. The diagnostics executable requires `--network` or `--intelligence` to perform its documented probes. The normal core tests use injected responses and do not access mail, network services, or language models.

## Formatting and checks

We use **swift-format**, bundled with Xcode, for both formatting and style linting. `.swift-format` sets four-space indentation and a 120-column target; the remaining rules use its defaults. VS Code and the command-line check use this same configuration. Long literals are preserved when wrapping would change their contents.

`scripts/verify.sh` checks style, runs the Swift Testing suite, builds the app and test bundles, and checks whitespace errors. Compiler warnings fail the core-test and local Xcode builds. Swift 6 language mode also enforces concurrency checking. UI automation is a separate task because it launches applications and interacts with the desktop.

`swift-format` checks syntax/style; compiler diagnostics and behavioral tests cover different kinds of mistakes. This setup needs no separate SwiftLint installation, formatter package, or Git hook. The official [Swift extension](https://github.com/swiftlang/vscode-swift), [swift-format](https://github.com/swiftlang/swift-format), and [Xcode adapter](https://github.com/SolaWing/xcode-build-server) document those tools.

## Understanding the code

| Location | Responsibility |
| --- | --- |
| `transorma/transormaApp.swift` | SwiftUI app entry point; creates the shared UI model. |
| `transorma/ContentView.swift` | Setup, activity, keep-list, and privacy screens. |
| `transorma/ProtectionModel.swift` | Loads settings, connects UI actions to storage, and runs the worker. |
| `mailextension/MessageActionHandler.swift` | Adapts incoming MailKit callbacks to the core policy. |
| `Sources/TransormaCore` | Message parsing, DKIM verification, classification, persistence, networking, and unsubscribe workflows. |
| `Sources/CMailSystem` | A small bridge to macOS's DNS resolver and HTML parser. |
| `Tests/TransormaCoreTests` | The same behavioral test sources run by SwiftPM and the Xcode core-test target. |
| `transormaUITests` | Tests the actual companion app with isolated settings. |
| `Package.swift` | Declares the reusable core library, diagnostics executable, and package tests. |
| `transorma.xcodeproj` | Defines app/extension packaging, signing, and Xcode test targets. |

An `import` names a module. `SwiftUI`, `MailKit`, and `FoundationModels` come from the macOS SDK. `TransormaCore` is our local Swift package. `Testing` and `XCTest` come from the developer toolchain. Those imports need target-specific compiler settings; adding arbitrary search paths in the editor can conceal a broken setup.

## If editor errors return

Run **Transorma: rebuild index**, then **Swift: Restart LSP Server** (or **Developer: Reload Window**). Rebuild after adding files or changing target membership. `scripts/index.sh` reads Xcode's compiler logs into the ignored `.compile` file; `buildServer.json` tells the language server where to get those settings. Build artifacts and machine-specific compiler paths stay out of Git. Replaying retained build logs also handles incremental builds that contain no compiler invocations.

If the build itself fails, address its first compiler error first. If only the editor fails, check **View → Output → Swift** and confirm that it uses `/Applications/Xcode-27.app`, then check that `xcode-build-server` is installed. The missing SweetPad formatter and old machine-specific build-server configuration have been replaced.
