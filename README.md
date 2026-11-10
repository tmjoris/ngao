# Ngao

[![CI](https://github.com/tmjoris/ngao/actions/workflows/ci.yml/badge.svg)](https://github.com/tmjoris/ngao/actions/workflows/ci.yml)

A mobile-banking client for iOS built the way a bank's security team would want it, around
the one problem every mobile money app eventually gets wrong: charging a customer twice.

*Ngao* is Swahili for shield.

```
Sources/NgaoCore   Pure Swift 6, builds on Linux. Transfer state machine, idempotent outbox,
                   limits, PIN and session policies. 20 XCTest cases.
iOS/               UIKit app, MVVM + Coordinators, programmatic layout, no storyboards.
                   Objective-C PIN pad and jailbreak module bridged into Swift.
                   XCTest + XCUITest, fastlane, CocoaPods (SwiftLint) + SPM.
tools/mockbank.py  Core-banking mock with idempotency and fault injection, stdlib only.
```

## The double-charge problem

A transfer request leaves the phone. The bank debits the account. The response is lost: the
train went into a tunnel, the app was killed, the load balancer timed out. The app shows
"failed", the customer taps "send" again, and is charged twice. Every Kenyan who has used
mobile money knows this story.

Ngao treats "no answer" as its own state and never lets it collapse into "failed":

```
 pending ──send──▶ submitted ──response──▶ confirmed
                      │                └──▶ failed(retryable?) ──send (same key)──▶ submitted
                      └──no answer──▶ unknown ──reconcile──▶ confirmed | failed | neverReceived
```

- **Idempotency key per intent, not per attempt.** Every retry of the same transfer sends
  the same `Idempotency-Key`. A bank that has already processed it returns the original
  receipt instead of debiting again.
- **`unknown` blocks the user.** The screen says "Do not send it again", the retry button is
  gone, and the only action is "Check now", which asks the bank what happened to that key.
- **The outbox is written before the first byte goes out.** A crash between "confirm" and
  "response" leaves a row; the next launch reconciles it before showing a balance.
- **Daily limits count `unknown` transfers.** A flaky network cannot be used to exceed the cap.
- **Three attempts, then stop.**

`Tests/NgaoCoreTests/OutboxTests.swift` drives these against a fake bank that really debits:
dropped response after commit, timeout before commit, crash mid-flight, duplicate submit. The
assertion in every case is `debits.count == 1` or `0`, never more.

## Security checklist

| Requirement | Where |
| --- | --- |
| Keychain, device-only, no iCloud sync | `KeychainStore` (`AfterFirstUnlockThisDeviceOnly`) |
| Biometric-gated secret, invalidated when biometrics change | `KeychainStore.Protection.biometric` (`.biometryCurrentSet`) |
| Face ID / Touch ID | `BiometricAuthenticator` (LocalAuthentication) |
| Certificate (SPKI) pinning on top of ATS | `PinnedSession` |
| App Transport Security, no exceptions | `project.yml` |
| PIN never in a text field: no autocorrect, clipboard or keyboard cache | `NGPinPadView` (Objective-C) |
| Shuffled keypad, shake on wrong PIN | `NGPinPadView` |
| Weak PIN rejection and progressive lockout that survives relaunch | `PinPolicy`, `PinLockout` |
| Inactivity timeout, background grace, absolute lifetime | `SessionPolicy`, `Session` |
| Blur before the app-switcher snapshot | `PrivacyShield` |
| Screenshot blocking for sensitive views | `ScreenshotGuard` |
| Jailbreak and debugger signals | `NGDeviceIntegrity` (Objective-C) |
| Account and phone masking everywhere | `Masking` |
| Outbox file: complete protection, excluded from backup | `FileOutboxStorage` |

## Running

```sh
swift test                              # core: state machine, outbox, policies
python3 -I tools/test_mockbank.py       # mock bank: idempotency and fault injection
python3 tools/mockbank.py               # http://127.0.0.1:8090, PIN 739142
```

iOS, on a Mac with Xcode 16:

```sh
brew install xcodegen
cd iOS && xcodegen generate && pod install && open Ngao.xcworkspace
```

Set `NGAO_API_BASE_URL` in `project.yml` to the mock bank (`http://127.0.0.1:8090` works on
the simulator; ATS allows loopback) or a real API. Set `NGAO_PIN_SHA256` to the SPKI hash
of its certificate to turn pinning on.

With the mock bank, try sending to a phone ending in any digits with the header trick from
`tools/mockbank.py` (`X-Fault: drop-after-commit`) or, in the UI tests, to `0712345699`,
which the scripted bank treats as "committed, response lost".

## Architecture

- **MVVM + Coordinators.** View controllers render and forward taps. View models hold state
  and talk to the API and the outbox. Coordinators own navigation and the session.
- **Objective-C where a bank actually has it.** The PIN pad and the device-integrity probe
  are `.m` files with a bridging header, nullability annotations and ARC.
- **Core Animation.** Dot fill and shake on the PIN pad; drawn check, cross and pulsing dots
  on the transfer result.
- **Dependency management.** SwiftPM for `NgaoCore`, CocoaPods for SwiftLint.
- **CI/CD.** Linux job runs the core and mock bank tests. macOS job generates the project,
  installs pods, runs XCTest and XCUITest. A gated fastlane lane uploads to TestFlight.

## Status

- [x] Core state machine, outbox, policies with tests (Linux CI)
- [x] Mock bank with idempotency and fault injection
- [x] iOS app: login, home, send money, status, cards; Keychain, pinning, shield; unit and UI tests green on a macOS runner
- [ ] Screenshots
- [ ] TestFlight
