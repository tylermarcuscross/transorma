# Release preparation

This file distinguishes implemented behavior from checks that require an actual developer account, a signed Mail extension, real model evaluation, or distribution metadata. App Review approval is Apple's decision; using public APIs and App Sandbox provides a viable route, not a guarantee.

## Account and tools

Paid Apple Developer Program enrollment is processing. Complete enrollment before provisioning App Groups and distributing the extension. For PCC, also enroll in Small Business and [request Apple's managed entitlement](https://developer.apple.com/private-cloud-compute). Apple currently limits eligibility to developers with fewer than two million first-time downloads.

Xcode 27 RC (`27A266a`) is installed at `/Applications/Xcode-27.app`. Use the final release toolchain for App Store submission. The shared scheme's Development configuration uses ad hoc signing and disposable settings without App Group entitlements. Debug and Release use the signing policy in `Config/Shared.xcconfig` and the target entitlements under `App/Resources` and `TransormaMailExtension/Resources`.

`fm` is optional developer tooling. Apple requires a privileged user to read and accept its machine-wide terms (`sudo fm license`). That acceptance was not performed. Native Foundation Models inference is independent of this CLI setup.

## Signed installation

1. Set the team's app and extension identifiers. Both targets must share the exact App Group in `SharedStore.groupIdentifier` and their entitlements. Xcode is configured for automatic signing and App Group registration.
2. Select Debug for the Transorma scheme's Run action and install the signed app into Applications. Retain Development in the checked-in shared scheme for routine local work; Release is used for archives.
3. Enable the extension in Mail and allow full message content access. Confirm the app shows a recent Mail heartbeat.
4. Use a dedicated test mailbox and sender you control. Confirm new signed promotions request Trash, transactional messages stay, and pausing protection cancels pending work. No actual email was sent or changed as part of this repository implementation.
5. Close the companion window, terminate/restart Mail, quit/reopen Transorma, and reboot with login launch enabled. Confirm queues resume, concurrent app/extension workers do not double-send, and interrupted POSTs show an unknown outcome.
6. Verify extension memory, inference latency, and Mail callback deadlines under large arrival bursts. The decision gate serializes timeout and queue commitment: if timeout wins, late assessment cannot enqueue an unsubscribe or request Trash. If commitment wins, the queue is saved before requesting Trash. Its synchronous storage operation can delay callback delivery under disk contention; sustained-load and platform deadline behavior still require measurement.

For catch-up, close Mail before sending controlled signed promotions and transactional fixtures, then reopen it with protection enabled. Confirm newly downloaded eligible messages are assessed automatically, supported promotions request Trash, transactions stay, and queued unsubscribes finish with the Transorma window closed. Repeat with messages read on another device, with the Mac waking, and with Transorma relaunched after jobs were queued. Count callbacks, decisions, requests, and preserved messages for bursts above two concurrent assessments and above the waiting limits (32 messages / 8 MB). Test slow inference past the 20-second decision deadline. Messages that time out or exceed capacity must remain in place without a late unsubscribe.

Separately verify that enabling protection does not claim to rescan mail already downloaded while protection was disabled. Compare the remaining-request count with persisted jobs, not the total messages in the inbox. Confirm delayed retries retain their scheduled time and interrupted requests with unknown outcomes are not replayed. The synthetic tests cover these queue rules; actual Mail download/relaunch and OS lifecycle behavior still require this signed installation check.

MailKit provides incoming-message decisions, not mailbox enumeration or post-hoc message movement. Do not advertise existing-inbox cleanup or operation with Mail closed. A web fallback may be unresolved after the message goes to Trash; this is shown in Activity.

## Intelligence evaluation

The on-device API and actual DNS/TLS have a separate synthetic diagnostic. Run the diagnostics on the final OS and signed builds. Extend them with a consented, redacted corpus of real promotions, newsletters, mixed receipts with advertisements, security alerts, multilingual mail, and prompt injections. Measure false positives, recall, latency, model unavailability, and context overflow. The current English rules prioritize preservation and have limited recall.

Require zero transactional or personal-mail deletions in the release validation corpus. Define and publish an acceptable error budget for a larger held-out corpus before broad rollout. Synthetic tests and model-generated confidence are insufficient evidence of quality. Apple's macOS 27 [Evaluations framework](https://developer.apple.com/videos/play/wwdc2026/241/) is an option for a larger evaluation suite.

Exercise HTML fallback with malicious hidden fields, deceptive labels, cross-origin redirects, stalled connections, HTTP framing variations, false success pages, login, CAPTCHA, and JavaScript-only sites. The model selects IDs from a code-created set; the application owns all side effects. This limits model authority, but cannot prove an authenticated sender's web page is truthful. Do not market arbitrary website automation.

Once PCC entitlement access is granted:

- Add `com.apple.developer.private-cloud-compute = true` to the provisioned executable that uses it. The existing runtime check requires the entitlement; user consent remains separate.
- Verify availability and failures on the signed app and extension independently. If PCC is only provisioned for the companion app, ensure web jobs are executed there before enabling the feature publicly.
- Test daily limits, network failures, region/device unavailability, and revocation. Local inference runs first, and unresolved cloud inference stops the job.
- Verify that the page excerpt and action labels are the only PCC inputs, and that the visible opt-in disclosure remains accurate. Regex redaction removes common URLs and email addresses, not every kind of personal information.

## Store and network review

Review the verifier and native HTTP parser independently before production. They use platform cryptography and TLS, with published signature interoperability vectors, but the surrounding protocol handling is new application code. The connection is pinned to a validated public IP and TLS verifies the original hostname; there is no DNS validation/connect race. No automatic cross-host navigation or browser sessions are used. Hosts requiring proxies, cookies, non-UTF-8 HTML, JavaScript, or unsupported HTTP behavior can fail safely.

The protected shared folder contains settings, bounded activity, pending unsubscribe URLs, and recent request fingerprints. A lock coordinates both processes; a completed atomic replacement commits a state change before Trash is returned. Expiry is enforced at the next worker/enqueue operation. No background process can purge storage while the application and extension are not running. Completed URLs are removed; hashed duplicate fingerprints can remain for seven days after clearing visible activity.

## App Store submission

- Produce and validate a developer-signed archive with the release Xcode toolchain. An unsigned Xcode 27 RC archive has passed local packaging checks; it is not a store-ready archive.
- Review the development icon in the signed app and Mail extension, and prepare final screenshots, description, support URL, and a publicly hosted privacy-policy URL. The personal-use UI has no dedicated privacy page; add an accessible policy before distribution. Hosting and App Store Connect metadata are not configured.
- Review the privacy manifests and App Store privacy answers against final behavior, including optional PCC and unsubscribe websites. The manifests currently declare no tracking, no developer-collected data, and no required-reason APIs. Revisit if storage, diagnostics, analytics, or APIs change.
- Explain the one-time consent, automatic website requests, Trash behavior, preserve-on-uncertainty policy, and limitations in reviewer notes. [RFC 8058 §3.2](https://www.rfc-editor.org/rfc/rfc8058) requires consent but leaves its timing and form unspecified; this app requests consent during setup.
- Provide a reproducible dedicated-mailbox test route and signed fixtures or a controlled sender for reviewers. Supply instructions for enabling Mail content access and testing with Apple Intelligence unavailable.
- Ensure public API and sandbox requirements under [App Review Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/), plus consent, minimization, and privacy disclosure under 5.1. No AppleScript, Accessibility automation, Full Disk Access, private Mail database access, or remotely downloaded executable code is used.

Do not claim Apple endorsement, guaranteed unsubscribe, zero classification errors, arbitrary-site coverage, or permanent background execution.
