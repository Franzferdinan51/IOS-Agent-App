# DualAgent

> One iOS app that talks to both **Hermes-WebUI** *and* **OpenClaw Gateways**,
> featuring lock-screen live activities, end-to-end encrypted sessions, and a
> native UI with on-device speech dictation.

DualAgent ships a colorful SwiftUI interface for chatting with AI agents
running on:

| Backend | What it is | Connection |
|---|---|---|
| **Hermes-WebUI** | The `hermes` reference web-stack (chat SSE over HTTPS) | Username/password login → cookie-based session |
| **OpenClaw Gateway** | The `openclaw` gateway (chat over WebSocket RPC) | QR pairing, gateway-token auth, full audit log |

You can switch backends at any time in **Settings → Backend** without losing
your local sessions or custom theme.

---

## Highlights

- 🔒 **Lock Screen Live Activity** — see the agent's tool, run-state, and
  (opt-in) a response excerpt on the Lock Screen and Dynamic Island
  (`AgentRunActivityAttributes`).
- 🎙️ **Composer dictation** — tap the mic in the chat composer to speak;
  live transcript flows into the message field via on-device speech
  recognition.
- 🔗 **Deep links** — `dualagent://chat/new`, `dualagent://chat/new?voice=1`,
  `dualagent://chat/new?profile=<name>`, `dualagent://session?id=<id>`. Wire
  Shortcuts / Action Button / iOS Spotlight.
- 🌗 **Adaptive glass & vibrant brand palette** — Hermes = indigo/cyan,
  OpenClaw = violet/orange. Both with translucent iOS-26 glass surfaces and
  Reduce-Transparency-friendly fallbacks.
- 🔁 **Pull-to-refresh on every list** — Sessions, Skills, Crons, Memory.
- 🔍 **Search everywhere** — every list tab has a `.searchable` filter.
- 🪪 **Imported / read-only sessions** are clearly badged and disable the
  composer instead of failing on send.
- 🔐 **OpenClaw pairing flow** — scan a QR code, device token persists in
  the iOS keychain; bootstrap token is never persisted.
- 📜 **Pure-Swift streaming** — Hermes SSE and OpenClaw WebSocket both funnel
  into `UnifiedChatEvent`; the UI doesn't care which.

---

## Project layout

```
DualAgent/
├── DualAgent/                     # App target source root
│   ├── Resources/Info.plist      # URL scheme, mic/speech/camera descriptions
│   ├── Networking/                # Backend protocol + Hermes / OpenClaw adapters
│   │   ├── Backend.swift          # Single Backend protocol (22 methods)
│   │   ├── HermesBackend.swift    # Hermes SSE + cookie session adapter
│   │   ├── OpenClawBackend.swift  # OpenClaw gateway adapter (RPC)
│   │   ├── OpenClawRPC.swift      # WS request/response + event subscription
│   │   ├── OpenClawPairing.swift  # QR-setup-code pairing driver
│   │   └── DualAgentDeepLink.swift # dualagent:// URL → AppState routing
│   ├── LiveActivities/            # AgentRunActivityAttributes, manager
│   ├── Feedback/Haptic.swift      # Centralized haptic API
│   ├── Features/                  # SwiftUI views (Sessions, Chat, Skills, ...)
│   └── Theme.swift                # Brand palettes + reusable card primitives
│
├── DualAgentLiveActivityWidget/   # App-extension target (WidgetKit)
│   ├── AgentRunLiveActivityWidget.swift
│   └── Info.plist
│
├── project.yml                    # XcodeGen → DualAgent.xcodeproj
├── .github/workflows/build-ios.yml  # CI build on push/PR
└── README.md                      # ← you are here
```

---

## Build & run

### Prerequisites
- macOS 15 or later
- Xcode 16+ with iOS 18 SDK (deployment target is iOS 18.0)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (one-time install)
  ```sh
  brew install xcodegen
  ```

### Generate the Xcode project
```sh
xcodegen generate
```
This reads `project.yml` and produces `DualAgent.xcodeproj`. Run this after
adding new source files so Xcode picks them up.

### Open in Xcode
```sh
open DualAgent.xcodeproj
```

### Build from CLI
```sh
xcodebuild \
  -project DualAgent.xcodeproj \
  -scheme DualAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

---

## Connecting a backend

### Hermes-WebUI
1. Launch the app.
2. On the onboarding screen, choose **Hermes** as the backend.
3. Enter your server URL (e.g. `https://your-host.example.com`), the
   password you set in `~/.hermes/.hermes-webui.env`, and tap **Connect**.

### OpenClaw gateway
1. On the gateway host, generate a one-time setup code:
   ```sh
   openclaw device.pair.setupCode
   ```
2. In the app, choose **OpenClaw**, then tap **Scan QR** (or paste the
   decoded setup payload).
3. The gateway issues a per-device token; the bootstrap token is discarded
   once the handshake completes. Subsequent launches auto-reconnect using
   the stored device token.

> **Tip.** You can also paste a gateway token directly (the QR-less admin
> path); see Settings → Backend → "Use token".

---

## Live activity / Dynamic Island

DualAgent renders an `AgentRunActivityAttributes` Live Activity whenever a
chat turn is active. The widget extension ships in the `PlugIns/` directory
of the built app bundle and runs as an `appex`. You should see:

- A pill in the Dynamic Island with status (`Thinking`, `Using tool`,
  `Responding`, `Complete`, `Cancelled`).
- A Lock-Screen card with the session title, current activity, and (if you
  opt in to "Show response text in Live Activity" in Settings) the latest
  response excerpt.

If ActivityKit is disabled in Settings → Face ID & Passcode → Allow Access
When Locked: ActivityKit → None, you'll see no lock-screen content. The
in-app status pill still appears in the chat header.

---

## Deep links

| URL | What it does |
|---|---|
| `dualagent://chat/new` | Open the New Session sheet |
| `dualagent://chat/new?voice=1` | Open the New Session sheet, auto-start dictation when the chat loads |
| `dualagent://chat/new?profile=<name>` | Pin the new session to a profile (Hermes namespaced) |
| `dualagent://session?id=<sessionID>` | Surface the Sessions tab and pre-populate search |

Test from CLI:
```sh
xcrun simctl openurl booted "dualagent://chat/new?voice=1"
```

---

## Configuration & storage

- **Credentials** are stored in the iOS keychain (`KeychainStore`).
- **Settings, theme, Live-Activity privacy preferences** are stored in
  `UserDefaults` via the `AppSettings` observable.
- **No API keys, tokens, or connection strings are committed to this repo.**
  Any default hostnames are placeholder example URLs (e.g. `example.com`)
  that you replace during onboarding.

---

## Troubleshooting

| Symptom | Try this |
|---|---|
| Live Activity never appears | Verify `NSSupportsLiveActivities` is `true` in `DualAgent/Resources/Info.plist`. Xcode 16 defaults to enable it; older projects need it set manually. |
| Dictation prompt never appears | Verify `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are both present in `Info.plist`. |
| OpenClaw pairing fails with `PAIRING_REQUIRED` | Approve the device from another paired client (`openclaw device.pair.approve <id>`), then retry. |
| Hermes chat shows 401 | Delete the stored credential in the iOS keychain (or reset the app) — the password may have been rotated on the server. |
| Build fails right after adding a file | You forgot to run `xcodegen generate`; re-run it so Xcode picks up the new source. |

---

## Contributing

Before opening a PR:

1. Run `xcodegen generate` and confirm `xcodebuild ... build` succeeds on a
   `iPhone 17` simulator destination.
2. Do not commit credentials, device tokens, or absolute hostnames. Use
   example.com placeholders.
3. Keep changes scoped — prefer additive commits, not drive-by refactors.
4. UI changes: include a screenshot in the PR description (saves a CI round-trip).

---

## Acknowledgements

Built on top of two upstream projects:

- [Hermes-WebUI](https://github.com/...) — the chat SSE protocol and lock-
  screen Live Activity patterns.
- [OpenClaw Gateway](https://github.com/openclaw/openclaw) — the verified
  WebSocket-RPC protocol (`docs/gateway/protocol.md`), gateway URL/scheme,
  and pairing choreography.

## License

DualAgent is released under the MIT License — see [`LICENSE`](./LICENSE).
