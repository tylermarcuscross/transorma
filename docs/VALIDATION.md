# Validation record — September 13, 2026

Environment: Apple silicon, macOS 27.0 RC (26A428), Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27 RC (27A266a) at `/Applications/Xcode-27.app`, macOS 27 SDK. The project selects this toolchain even though system-wide `xcode-select` still points to Command Line Tools.

Completed locally:

- Core Swift package builds in Swift 6 language mode with application-extension API restrictions.
- 23 Swift Testing tests pass, including parameterized RSA/Ed25519 signatures, published RFC 8463 interoperability vectors, tampering, malformed mail, MIME transfer decoding, public-IP filtering, HTTP framing, duplicate prevention, consent/keep-list enforcement, interrupted jobs, one-click handling, static-form navigation, and rejection of invented model actions.
- Read-only live system DNS lookup and public-IP-pinned TLS request to `https://example.com/` succeed (HTTP 200).
- Native on-device Foundation Models inference passes three synthetic classifications: promotion, mixed receipt with advertising, and an instruction-injected security alert. It also selects the expected action from a synthetic unsubscribe form. No live unsubscribe URL is requested by these diagnostics.
- The MailKit adapter passes Swift 6 type checking with `-application-extension` against the macOS 27 SDK.
- The SwiftUI companion app compiles and links with the native compiler into a local preview. The preview launches with a fresh temporary store and no unsubscribe worker. An image of the app's own window is rendered and inspected at `.build/Preview/Transorma.png`.
- Project, entitlement, and privacy property lists validate; shell scripts pass syntax checking; `git diff --check` passes.
- Full Xcode 27 Debug build succeeds for the companion app, embedded Mail extension, diagnostics, core-test bundle, and UI-test runner. The local command uses ad hoc signing and omits distribution App Groups. Swift compiler warnings are treated as errors.
- The shared Xcode scheme runs all 23 core tests and both UI tests successfully. UI automation verifies protection opt-in/pause and access to the privacy page. It uses `--ui-testing`, temporary storage, and no unsubscribe worker.
- An unsigned Release archive succeeds at `.build/Archives/Transorma.xcarchive`, containing the arm64 app and embedded extension. This verifies compilation and packaging, not distribution signing or App Store validation.
- `swift-format` style linting passes across the Swift sources, tests, and tools using the shared four-space/120-column configuration.
- Direct SourceKit-LSP checks against the VS Code configuration return no diagnostics for the app entry point, UI model, Mail handler, Foundation Models implementation, core tests, UI tests, and diagnostics tool. Hover and Go to Definition resolve `SharedStore` across modules to its source file. The formatter provider corrects an intentionally misindented in-memory line to four spaces; this probe does not change the source file.
- Xcode's LLDB debug adapter successfully launches the local app with `--ui-testing` and hits a source breakpoint in `ProtectionModel.init`. No developer signing identity is required for this local debugging workflow.

Not established:

- Developer-signed archive export or App Store validation. The local unsigned archive is not ready for upload.
- Installed, signed MailKit callback behavior, real mailbox actions, sustained arrival loads, or extension lifecycle/inference timing. No mailbox was accessed or modified.
- Production classification accuracy. The synthetic checks are tiny smoke tests; they are not held-out accuracy measurements.
- PCC inference. Paid developer enrollment is processing; Small Business enrollment and the managed PCC entitlement remain pending. The public macOS 27 calls compile, but that path has not run.

Reproduce local builds, style checks, debugging, and tests using [the development guide](DEVELOPMENT.md). To reproduce the unsigned Release archive:

```sh
DEVELOPER_DIR=/Applications/Xcode-27.app/Contents/Developer xcodebuild \
  -project transorma.xcodeproj -scheme Transorma -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/Release \
  -archivePath .build/Archives/Transorma.xcarchive \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES archive
```

Follow [release preparation](RELEASE.md) before enabling the extension on a primary mailbox or publishing it.
