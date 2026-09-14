# Validation record — September 13, 2026

Environment: Apple silicon, macOS 27.0 RC (26A428), Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27 RC (27A266a) at `/Applications/Xcode-27.app`, macOS 27 SDK. Project tooling selects this Xcode even when system-wide `xcode-select` points to Command Line Tools.

## Menu bar accent

- The menu bar T now has a small red paper fold. The 18-point vector asset supplies black/light and white/dark variants, using original rendering to preserve the accent.
- `make build`, `make lint`, and whitespace checks pass. Both compiled asset appearances and the actual menu bar icon were visually reviewed. Temporary previews remain ignored under `.build/MenuBarAccentReview`.

## Simplified activation and Mail setup

- The first Settings card contains only **Activate Transorma** and its switch. The Mail card now has a primary action, two numbered setup steps, and an expandable background explanation.
- Verified `mail-pref-pane://extensionspref` switches Mail from General to Extensions settings. Clicking **Open Mail Settings** in the sandboxed Development app also launches Mail directly into Extensions when Mail is closed. This check did not enable the extension or change its permissions.
- The three existing UI checks pass; activation was rerun after the final card-width adjustment. Strict formatting and whitespace checks pass. The normal and minimum-width layouts were visually reviewed, with temporary helpers and screenshots ignored under `.build/MailSetupReview`.

## Mail settings artwork

- Added `icon-menu` and `icon-preferences` template image assets to the extension. Mail's list and details panel both display the Transorma T after a normal Mail quit and relaunch; this was verified in the actual Extensions settings window on macOS 27 RC.
- `make build` and `make archive-unsigned` pass. Bundle image lookups confirm both named assets load from Development and archived Release extensions, with template rendering and the intended 18/64-point sizes. Asset JSON, SVG, and whitespace checks pass.
- Screenshots and temporary diagnostics remain ignored under `.build/MailIconReview`. Verification selected the extension's settings row without enabling it or changing its permissions. Mail processing and signed integration remain separate checks.

## Keep-list removal

- Removed the keep-list controls, draft state, app actions, and Activity's per-sender action. Obsolete keep-list UI and validation tests were removed; settings persistence and storage-failure coverage remain.
- `make test`: **57 core tests, eight app model tests, and three UI tests** pass. The app and extension build successfully; strict formatting and whitespace checks pass. The editor index was refreshed after removing `KeepListView.swift`.
- Existing sender exclusions in saved settings are still honored by the core. No storage migration, cancellation, undo, or resubscription feature was added.

## Earlier Settings and Activity UI

- `make test-ui`: all **four UI tests** pass with the two-section navigation and simplified status menu. They cover opt-in/pause, keep-list validation and draft persistence, Settings routing from Activity and a closed window, ⌘N/⌘, shortcuts, single-window reuse, and Quit. The two affected screen tests also pass after the final switch and empty-state alignment adjustments.
- The native Development app and extension build successfully. Formatting and whitespace checks pass. SourceKit-LSP returns no diagnostics for all five app view files, the app entry point/model, manifest, and the existing core/extension/test checks. The refreshed editor index includes the renamed `SettingsView.swift` and seven compiled modules plus the manifest.
- Settings, Activity, and the status menu were visually reviewed using UI test screenshots. Captures remain ignored under `.build/SettingsReview` and `.build/SettingsReviewFinal`. The dedicated Privacy view was removed; disclosure text beside the intelligence controls remains.

## Automatic catch-up

- `make test`: **57 core tests, nine app model tests, and four UI tests** pass on Xcode 27 RC. The Development build includes the companion app and embedded extension. UI tests verify the catch-up explanation and shared protection status, along with existing navigation and menu behavior.
- `make test-core`: **57 Swift Testing tests, 119 cases after parameter expansion**, pass independently through SwiftPM, using synthetic messages, injected services, and temporary stores.
- New regressions cover bursts beyond two active assessments, bounded waiting by count and bytes, queued cancellation/expiry, and protection paused while waiting. Worker tests drain persisted bursts and arrivals during a pass without repeating completed requests; they preserve retry dates and unknown outcomes. App model tests verify startup drains more than the former three-job batch, wake signals resume newly persisted work before the polling interval, progress reflects saved jobs, and cancellation ends the processing loop.
- `make lint` passes, and `make archive-unsigned` produces the Release archive at `.build/Archives/Transorma.xcarchive`. Direct SourceKit-LSP checks return no diagnostics for the manifest and the same nine Swift files listed below; hover, definition lookup, and in-memory formatting still work.
- Actual Mail close–receive–reopen behavior, workspace wake notifications, and processing after login without a dashboard still require the signed installation checks in [release preparation](RELEASE.md#signed-installation). No mailbox was accessed or modified. The Development configuration remains isolated and does not process real mail.

## Earlier project validation

- `make test-core`: **50 Swift Testing tests, 109 cases after parameter expansion**, pass independently through SwiftPM. Tests use injected DNS, HTTP, and intelligence with temporary stores; they do not contact unsubscribe sites or access a mailbox.
- `make verify`: strict formatting, native Development build, **50 core tests and six app model tests**, and whitespace checks pass. The build includes the app, embedded extension, diagnostics, and test bundles. Actual compiler commands confirm warnings-as-errors for both native and Swift package targets.
- `make test-ui`: **four UI tests** pass. They cover protection opt-in/pause, privacy access, keep-list validation and recovery, draft persistence across navigation, sender removal, menu/dashboard protection state, and closing/reopening the single dashboard window. Test setup uses the visible Open Transorma menu action because XCTest's launch omits the dashboard when a menu bar scene is present; normal app launch was separately verified to present its window. The actual Development app uses disposable settings with no worker. A test screenshot is attached to the Xcode result bundle and was exported for visual inspection.
- `make archive-unsigned`: Release archive succeeds at `.build/Archives/Transorma.xcarchive`. The arm64 `Transorma.app` contains `TransormaMailExtension.appex`; both include their privacy manifests. Bundle identifiers remain `me.tylercross.transorma` and `me.tylercross.transorma.mailextension`. The extension's MailKit entry point resolves to its renamed module.
- Development and Release app/extension bundles include the shared Icon Composer artwork, compiled `AppIcon.icns` and `Assets.car`, and matching icon metadata. Native macOS 27 light, dark, and small renders were visually inspected. Menu bar artwork uses a separate monochrome template SVG.
- The subsequent monochrome revision passes `make build`, `make lint`, and all four existing UI tests. The enlarged icon was reviewed in default/dark appearances and at small size; actual app windows were inspected in light and dark appearances for sidebar, text, and control contrast. Visual-review helpers and screenshots remain ignored under `.build/`; no screenshot-only runtime code was added to the app.
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
