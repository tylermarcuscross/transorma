# Working on Transorma

Xcode owns the app, Mail extension, signing, and UI tests. Swift Package Manager owns the shared core and diagnostics tool. VS Code uses these same targets and compilers through the official Swift extension and `xcode-build-server`.

There is no application server to build or run. The **build server** translates Xcode compiler settings for the editor: it tells SourceKit-LSP which SDK, module, and flags apply to each file.

## Setup

1. Install Xcode 27 or newer and finish its first launch.
2. Open the repository folder in VS Code and install its recommended [Swift extension](https://github.com/swiftlang/vscode-swift).
3. Install the one editor adapter: `brew install xcode-build-server`.
4. Run `make doctor`, then press **⇧⌘B** to build.
5. Run **Developer: Reload Window** after changing the toolchain or opening this refactored workspace with old diagnostics.

The checked-in editor settings select `/Applications/Xcode-27.app`. If your installation has a different name, change `swift.path` and the two `DEVELOPER_DIR` settings in `.vscode/settings.json`. These settings configure different processes; VS Code does not generally expand launch/task variables inside arbitrary extension settings.

Terminal commands honor an explicit `DEVELOPER_DIR`, then look for Xcode 27+ using `xcode-select`, `/Applications/Xcode-27.app`, and `/Applications/Xcode.app`. For example:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make doctor
```

Selecting Xcode in **Xcode → Settings → Locations → Command Line Tools** also configures ordinary terminals. No separate Swift installation, formatter package, or model download script is required.

## VS Code profiles

Use a dedicated **Transorma** profile to keep work-repository extensions and settings out of this project. VS Code remembers the profile associated with a folder and activates it when that folder is opened again. The Default profile keeps its existing configuration. [VS Code profiles](https://code.visualstudio.com/docs/configure/profiles) are local editor preferences, so this association is not committed to the repository.

To set this up on another machine, create an empty profile named **Transorma** using **Profiles: New Profile** in the Command Palette, install the recommended Swift extension, and open this repository with that profile. Swift installs its LLDB debugger dependency. Add Codex or other tools you use here separately; appearance extensions can also be installed in the profile.

The equivalent [CLI commands](https://code.visualstudio.com/docs/configure/command-line) are:

```sh
code . --profile Transorma
code --install-extension swiftlang.swift-vscode --profile Transorma
```

The first command creates the profile if necessary and associates it with the repository. To activate an existing profile in an already open window, use **Profiles: Switch Profile → Transorma**. On macOS, **Shell Command: Install 'code' command in PATH** makes `code` available in a terminal.

For a one-off exception, an extension's gear menu has **Disable (Workspace)**. The recommendations in `.vscode/extensions.json` suggest useful extensions; they do not disable unrelated ones or act as an allowlist. Use a profile when both extension availability and user settings need to differ by project. Settings or extensions explicitly applied to all profiles remain shared.

## Workspace and repository layout

Top-level maintained folders use capitalized names: `App`, `Config`, `Docs`, `Scripts`, `Sources`, `Tests`, and `TransormaMailExtension`. VS Code sorts folders alphabetically and hides generated state so those folders are easy to scan. Shared editor and formatting configuration remains visible at the root.

`Transorma.xcodeproj` is Xcode's project bundle, a directory that Finder and Xcode present as a document. It defines the app/extension/test targets, resource membership, and shared scheme. `Package.swift` defines the shared Swift package; it does not replace the native project's app packaging and signing setup. The project bundle belongs in Git. VS Code hides it from Explorer because everyday code edits happen in the source folders. Use **Transorma: open Xcode** or `make xcode` to open it. To inspect its files directly, disable the `Transorma.xcodeproj` entry in the workspace's `files.exclude` setting.

All command-line build products, archives, test results, and index logs go under `.build/`. The editor adapter also requires `.compile` at the repository root. Both are ignored by Git and hidden in Explorer. `make clean` removes `.build`, `.compile`, and its lock; the next `make build` regenerates the app and editor index. SwiftPM's generated workspace and Xcode's `xcuserdata` are ignored; useful shared configuration can still be committed. [VS Code's workspace settings](https://code.visualstudio.com/docs/configure/settings#_workspace-settings) control visibility independently of Git tracking.

Track source, resources, entitlements, privacy manifests, shared schemes, build configuration, editor tasks, and documentation. Keep personal Xcode window/scheme state and generated outputs out of commits. Swift's automatic launch-configuration generation is disabled so the three intentional F5 configurations stay stable.

Third-party attribution lives in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), linked from the README and the published test-vector source. The notices remain part of the repository; their license text is preserved.

## Everyday commands

`make` lists the available commands. The Makefile calls Apple's native tools directly; the same commands run from VS Code tasks and a terminal.

| Action | VS Code | Terminal |
| --- | --- | --- |
| Build app, extension, diagnostics, and test bundles | **⇧⌘B** | `make build` |
| Debug the companion app | **F5 → Transorma: isolated UI** | `make run` opens it without a debugger |
| Open the native project | **Transorma: open Xcode** | `make xcode` |
| Run core tests | **Transorma: test core** | `make test-core` |
| Run core and app model tests | **Transorma: test unit** | `make test-unit` |
| Run all Xcode tests | **Transorma: test all** | `make test` |
| Run only UI automation | **Transorma: test UI** | `make test-ui` |
| Format Swift | Save a file; **Transorma: format** for all files | `make format` |
| Check style | **Transorma: lint** | `make lint` |
| Validate before sharing changes | **Transorma: verify** | `make verify` |
| Refresh editor compiler settings | **Transorma: refresh index** | `make index` |
| Clean build and refresh editor settings | **Transorma: rebuild index** | `make reindex` |
| Check the toolchain | **Transorma: doctor** | `make doctor` |
| Validate Release packaging without signing | | `make archive-unsigned` |
| Remove generated build output and editor indexes | | `make clean` |

`make verify` checks formatting, builds the app and extension, runs core and app model tests through Xcode, and checks whitespace. Hosted app model tests can launch the companion app. `make test` also executes the UI tests, which drive desktop interactions and are separate from quick verification. The unsigned archive validates Release compilation and packaging; distribution still requires a signed archive and release checks.

Native command examples, after selecting the right toolchain:

```sh
xcodebuild -project Transorma.xcodeproj -scheme Transorma \
    -configuration Development -destination 'platform=macOS' \
    -derivedDataPath .build/Xcode build-for-testing
swift test
swift format lint --strict --recursive Package.swift App TransormaMailExtension Sources Tests
```

The build and test commands refresh VS Code settings automatically when the adapter is installed. `make index` can also replay compiler logs after a build done outside the Makefile, provided that build used `.build/Xcode` and the Development configuration.

## Xcode and development isolation

Open `Transorma.xcodeproj` and select the shared **Transorma** scheme. **⌘R** builds and runs the companion app; **⌘U** runs the scheme's tests. The scheme uses **Development** for Run and Test and **Release** for Archive.

| Configuration | Purpose |
| --- | --- |
| Development | Ad hoc signing, disposable app settings, no unsubscribe worker, no App Group registration. Safe for learning the UI and setting breakpoints without an enrolled account. |
| Debug | Real App Group and Mail integration with development signing and a provisioned developer team. |
| Release | Optimized production build with distribution signing configured in Xcode. |

`Config/Shared.xcconfig` contains common compiler settings. `Development.xcconfig`, `Debug.xcconfig`, and `Release.xcconfig` express configuration differences. Development isolation is selected at compile time, so F5 and `make run` do not need a special launch argument. Settings reset on each launch; login-item registration is unavailable in this mode.

To test real Mail integration, use Debug in the scheme and configure the team and App Group as described in [release preparation](RELEASE.md). Keep the checked-in shared scheme on Development for routine work.

SwiftUI `#Preview` declarations render the same app views with isolated state in Xcode. `make run` and F5 launch the actual app; UI tests attach a screenshot to their Xcode result bundle.

## Mail setup in Settings

The first card contains only the **Activate Transorma** switch. The Mail setup card has two steps and an **Open Mail Settings** link styled as the primary action. It opens `mail-pref-pane://extensionspref`, a URL handled by the installed Mail app on macOS 27 RC. This is a normal SwiftUI `Link`; it does not use AppleScript, Accessibility automation, or change Mail permissions. Mail's own checkbox and consent prompt still control extension access.

Apple does not document this pane URL as a MailKit API. Verify that it opens Extensions after macOS updates; the visible **Mail → Settings → Extensions** path remains the manual route. Background behavior and its limitations are available in an expandable explanation below the setup steps.

## App and menu bar artwork

`App/Resources/AppIcon.icon` is the editable Icon Composer source. It contains a graphite background and two SVG layers forming a large white T with a silver paper fold. The monochrome palette takes its cues from black-and-white photographs of industrial mail sorting. Xcode compiles that same source into both the companion app and Mail extension, including the native Liquid Glass appearances and fallback icon resources. Open the `.icon` bundle in Xcode's **Open Developer Tool → Icon Composer** to adjust its layers.

The menu bar uses `App/Resources/Assets.xcassets/MenuBarIcon.imageset`: a black or white T with a small vermilion paper fold. The asset catalog supplies light and dark SVG variants; original rendering preserves the red detail. The menu remains available after the window closes and offers **Open Transorma** (⌘N), **Settings…** (⌘,), and **Quit** (⌘Q). Open restores the selected section; Settings selects Settings in the same window. The shortcuts also appear in the app's standard menus and work while Transorma is active; they are not global hotkeys. Development builds still use isolated settings and no worker.

Mail's **Settings → Extensions** uses named images from the extension bundle rather than its app-icon metadata. `TransormaMailExtension/Resources/Assets.xcassets` supplies `icon-menu` for the extension list and `icon-preferences` for the details panel. These use the menu bar's T geometry at 18 and 64 points, with vector preservation and monochrome template rendering so Mail supplies the appearance and selection colors. Keep the T geometry aligned across the menu bar variants and Mail assets when updating the mark. These resource names were verified on macOS 27 RC; recheck the panel when upgrading macOS. Mail caches the images, so quit and reopen Mail after rebuilding if it still shows the puzzle-piece fallback. No extra extension capabilities or runtime API calls are needed.

Mail also generates the details heading as **extension name + version + “from” + containing app name**. The “from Transorma” text identifies the companion app. MailKit exposes no supported heading override to substitute an author or hide the version. Keep the app's display name and valid app/extension version metadata intact; this heading is controlled by Mail.

In signed Debug and Release builds, the application delegate starts queue processing at launch without needing the dashboard to appear. Pending requests resume on Mac wake and Mail launch/activation, with a 15-second poll for shared queue changes and scheduled retries. Settings and Activity show remaining unsubscribe requests. Mail itself supplies new downloads, including messages that arrived while it was closed; these events cannot rescan an existing inbox. See the [catch-up validation steps](RELEASE.md#signed-installation) before testing against a real account.

The app uses a vivid vermilion `AccentColor`: `#DF3026` in light appearance and a brighter `#FF4B3E` in dark appearance. Native sidebar icons, selection, and active controls pick up this accent against neutral surfaces. Sidebar selection follows the system's contrasting foreground, while status labels retain their text and symbols so meaning does not depend on color. The menu bar's paper fold uses the same reds; the app icon and Mail settings artwork remain monochrome.

Rendered previews and compiled icon binaries belong under `.build/`; the small vector sources and Icon Composer document belong in Git. [Apple's Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) describes the native layered format.

## Formatting and code checks

We use Xcode's bundled **swift-format** for formatting and strict style linting. `.swift-format` sets four-space indentation and a 120-column target; other rules retain the tool's defaults. The official Swift extension uses the same formatting technology on save. Compiler warnings are errors in both native targets (`Config/Shared.xcconfig`) and Swift package targets (`Package.swift`). Swift 6 language mode enforces concurrency checking.

Formatting, compiler diagnostics, and behavioral tests check different things. This setup does not require SwiftLint, a Git hook framework, Fastlane, or a project generator. [swift-format's documentation](https://github.com/swiftlang/swift-format) describes its formatting and lint commands.

The two remaining scripts handle environment integration:

- `Scripts/toolchain.sh` selects and validates Xcode before executing a native command.
- `Scripts/editor.sh` starts the editor adapter or rebuilds its compiler database from Xcode logs. It retains current Development settings, resolves source-file membership, removes deleted files, and atomically replaces the generated `.compile` file.

The [adapter documentation](https://github.com/SolaWing/xcode-build-server) explains why SourceKit-LSP needs these Xcode build settings. Build products, compiler databases, and machine-generated paths are ignored by Git.

## Code map

| Location | Responsibility |
| --- | --- |
| `App/TransormaApp.swift` | App composition and application lifetime. |
| `App/AppModel.swift` | Observable UI state and actions backed by shared storage. |
| `App/Views` | Settings and Activity navigation, menu bar, and window commands. |
| `TransormaMailExtension` | MailKit callbacks and extension packaging. |
| `Sources/TransormaCore/Mail` | Byte-preserving message parsing and signature verification. |
| `Sources/TransormaCore/Protection` | Settings, classification policy, and message assessment. |
| `Sources/TransormaCore/Unsubscribe` | Queue jobs, page interpretation, and unsubscribe workflows. |
| `Sources/TransormaCore/Infrastructure` | Persistence, HTTPS, and Apple Intelligence integration. |
| `Sources/CMailSystem` | The macOS DNS and HTML parser bridge. |
| `Sources/TransormaDiagnostics` | Explicit live network/model smoke checks. |
| `Tests/TransormaCoreTests` | Core tests shared by SwiftPM and Xcode. |
| `Tests/AppModelTests` | App state and settings behavior. |
| `Tests/AppUITests` | The actual companion app using isolated settings. |
| `Package.swift` | Core package, system bridge, diagnostics, and core tests. |
| `Transorma.xcodeproj` | App/extension packaging and native test targets. |

An `import` names a module, not a folder. `SwiftUI`, `MailKit`, and `FoundationModels` come from the macOS SDK. `TransormaCore` is our local package. `Testing` and `XCTest` come from the developer toolchain. The concern folders inside TransormaCore all remain part of that one module.

The two diagnostics F5 configurations explicitly choose network or intelligence probes. Network diagnostics use public DNS and `example.com`; intelligence diagnostics submit synthetic examples to the on-device model. Normal tests inject responses and do not access a mailbox or send unsubscribe requests.

## If editor errors return

Run **Transorma: rebuild index**, then **Swift: Restart LSP Server** or **Developer: Reload Window**. Build after moving files, adding files, or changing target membership. Xcode's synchronized folders keep source membership aligned with the files you edit in VS Code.

A missing import usually indicates incorrect compiler settings rather than a dependency to install. If the build fails, fix its first compiler error. If only the editor fails, inspect **View → Output → Swift** and confirm the selected Xcode path and the adapter reported by `make doctor`. The parser's latest output is in `.build/index.log`.

Incremental builds sometimes contain no compiler commands, and Xcode rotates older logs. `make index` retains valid settings from the previous index, then applies the newest Development commands from available logs. It refreshes source membership from current response files and discards settings for another toolchain or SDK. `make reindex` creates fresh logs and settings after a clean build.

`Package.swift` is compiled separately by SwiftPM, so it needs its own editor settings. `make index` adds the selected toolchain's `PackageDescription` module path and the manifest's `swift-tools-version` to the compiler database. Run it after changing that version or switching Xcode. This fixes missing-module errors in the manifest while keeping normal compiler diagnostics enabled.

## Working directly on main

This MVP uses direct commits to `main`; pull requests are optional. Before starting new work, update with `git pull --ff-only`. Before committing, run `make verify`, stage the intended changes, and review `git diff --cached`. Commit, then run `git push origin main`. GitHub currently has no active protection rule requiring pull requests on this branch. A normal push will reject conflicting remote changes, allowing you to integrate them before trying again.
