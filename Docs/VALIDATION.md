# Validation record — September 13, 2026

Environment: Apple silicon, macOS 27.0 RC (26A428), Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27 RC (27A266a) at `/Applications/Xcode-27.app`, macOS 27 SDK. Project tooling selects this Xcode even when system-wide `xcode-select` points to Command Line Tools.

## Refactored project

- `make test-core`: **50 Swift Testing tests, 109 cases after parameter expansion**, pass independently through SwiftPM. Tests use injected DNS, HTTP, and intelligence with temporary stores; they do not contact unsubscribe sites or access a mailbox.
- `make verify`: strict formatting, native Development build, **50 core tests and six app model tests**, and whitespace checks pass. The build includes the app, embedded extension, diagnostics, and test bundles. Actual compiler commands confirm warnings-as-errors for both native and Swift package targets.
- `make test-ui`: **three UI tests** pass. They cover protection opt-in/pause, privacy access, keep-list validation and recovery, draft persistence across navigation, and sender removal. The actual Development app uses disposable settings with no worker. A test screenshot is attached to the Xcode result bundle and was exported for visual inspection.
- `make archive-unsigned`: Release archive succeeds at `.build/Archives/Transorma.xcarchive`. The arm64 `Transorma.app` contains `TransormaMailExtension.appex`; both include their privacy manifests. Bundle identifiers remain `me.tylercross.transorma` and `me.tylercross.transorma.mailextension`. The extension's MailKit entry point resolves to its renamed module.
- Direct SourceKit-LSP checks return no diagnostics for the app entry point, app model, Mail handler, Foundation Models implementation, core tests, app model tests, UI tests, and diagnostics. Hover and Go to Definition resolve `SharedStore` to its moved source file. The formatter corrects an intentionally misindented in-memory line to four spaces without changing the file.
- Xcode's LLDB adapter launches the Development app without special launch arguments and hits a source breakpoint in `AppModel.init`.
- The editor compiler database is rebuilt from current Development logs, including after an archive. It includes seven compiled modules and filters moved/deleted source paths.
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
