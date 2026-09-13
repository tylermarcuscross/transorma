# Validation record — September 13, 2026

Environment: Apple silicon, macOS 27.0 RC (26A428), Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27 RC (27A266a) at `/Applications/Xcode-27.app`, macOS 27 SDK. Project tooling selects this Xcode even when system-wide `xcode-select` points to Command Line Tools.

## Refactored project

- `make test-core`: **50 Swift Testing tests, 109 cases after parameter expansion**, pass independently through SwiftPM. Tests use injected DNS, HTTP, and intelligence with temporary stores; they do not contact unsubscribe sites or access a mailbox.
- `make verify`: strict formatting, native Development build, **50 core tests and six app model tests**, and whitespace checks pass. The build includes the app, embedded extension, diagnostics, and test bundles. Actual compiler commands confirm warnings-as-errors for both native and Swift package targets.
- `make test-ui`: **four UI tests** pass. They cover protection opt-in/pause, privacy access, keep-list validation and recovery, draft persistence across navigation, sender removal, menu/dashboard protection state, and closing/reopening the single dashboard window. Test setup uses the visible Open Transorma menu action because XCTest's launch omits the dashboard when a menu bar scene is present; normal app launch was separately verified to present its window. The actual Development app uses disposable settings with no worker. A test screenshot is attached to the Xcode result bundle and was exported for visual inspection.
- `make archive-unsigned`: Release archive succeeds at `.build/Archives/Transorma.xcarchive`. The arm64 `Transorma.app` contains `TransormaMailExtension.appex`; both include their privacy manifests. Bundle identifiers remain `me.tylercross.transorma` and `me.tylercross.transorma.mailextension`. The extension's MailKit entry point resolves to its renamed module.
- Development and Release app/extension bundles include the shared Icon Composer artwork, compiled `AppIcon.icns` and `Assets.car`, and matching icon metadata. Native macOS 27 light, dark, and small renders were visually inspected. Menu bar artwork uses a separate monochrome template SVG.
- Direct SourceKit-LSP checks return no diagnostics for `Package.swift`, the app entry point, app model, menu bar view, Mail handler, Foundation Models implementation, core tests, app model tests, UI tests, and diagnostics. An intentionally invalid manifest expression still produces a compiler diagnostic. Hover and Go to Definition resolve `SharedStore` to its moved source file. The formatter corrects an intentionally misindented in-memory line to four spaces without changing the file.
- Xcode's LLDB adapter launches the Development app without special launch arguments and hits a source breakpoint in `AppModel.init`.
- The editor compiler database is rebuilt from current Development logs, including after an archive. It includes seven compiled modules plus separate `PackageDescription` compiler settings for the manifest, and filters moved/deleted source paths.
- An isolated index regression verifies that rotating Xcode logs and incremental builds retain settings for untouched modules. Current settings replace older ones; removed response files/sources, other toolchains/SDKs, and Release commands are excluded. A final `make reindex` restored all seven modules and the manifest, followed by clean diagnostics for all ten checked files.
- The local Transorma VS Code profile contains Swift, LLDB DAP, Codex, and vscode-icons; the Default profile retains its existing 46 extensions. The repository's folder association points to Transorma. Profiles remain local preferences; no editor profile state is committed.
- Native target source folders, resource paths, configurations, property lists, editor/asset JSON, shell syntax, and `git diff --check` validate. Stale generated 2025 comments and references to removed command scripts are gone.
- Workspace hygiene was verified with `make clean` followed by `make verify`, `make test-ui`, and `make archive-unsigned` using `Transorma.xcodeproj` and `Scripts/`. All pass. Case-only renames to `Docs/`, `Scripts/`, and the project bundle are recorded explicitly in Git. Personal Xcode state is untracked, and generated output stays ignored. A quick scan of current files and reachable Git history found no credentials or committed build artifacts.

The core regression suite includes published DKIM vectors, signature/header tampering, MIME decoding, message preservation rules, URL/IP filtering, HTTP framing, request deduplication, interrupted jobs, and bounded page navigation. New concurrency coverage verifies callback timeout versus queue commitment, reentrant completion, cross-process settings mutations, live claim ownership, and consent changes during connection setup or inference. PCC authorization tests simulate local inference followed by opt-out, protection/AI changes, a kept sender, or an expired claim; they do not call PCC.

Xcode 27 RC emits tooling messages such as skipped App Intents metadata extraction for targets without App Intents. These do not represent Swift compiler diagnostics or test failures.

## Earlier same-machine live smoke checks

Before the architecture refactor, system DNS lookup and a public-IP-pinned TLS request to `https://example.com/` succeeded with HTTP 200. On-device Foundation Models passed three synthetic classification examples (promotion, receipt with advertising, instruction-injected security alert) and selected an expected synthetic unsubscribe-page action. These were small smoke checks, not production accuracy measurements. The diagnostics executable remains available through the VS Code launch configurations and `make build-diagnostics`; live probes run only when explicitly selected.

## Not established

- Developer-signed archive export or App Store validation. The unsigned archive is not ready for upload.
- Installed, signed MailKit callbacks, real mailbox actions, sustained arrival loads, or extension lifecycle/inference timing. No mailbox was accessed or modified during this refactor.
- Production classification accuracy or arbitrary-site unsubscribe coverage.
- Actual PCC inference. Developer enrollment and the required managed entitlement remain separate from compilation and simulated authorization tests.

Reproduce the checks using the [development guide](DEVELOPMENT.md). Follow [release preparation](RELEASE.md) for signed integration, model evaluation, and distribution.
