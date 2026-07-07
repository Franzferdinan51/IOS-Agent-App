# DualAgent iOS App

A native iOS application that can communicate with either a Hermes-webui server or an OpenClaw Gateway, combining the polished UI/UX of Hermex with the rich device-capability features of OpenClaw.

## Features

- **Dual Backend Support**: Seamlessly switch between Hermes-webui and OpenClaw Gateway at runtime.
- **Unified Chat Interface**: Real-time streaming chat with support for attachments, tool calls, reasoning, and model selection.
- **Session Management**: Browse, search, pin, archive, and resume conversations.
- **Workspace Exploration**: Browse server file systems, preview text and binary files.
- **Device Integration (OpenClaw)**: Access camera, microphone, location, contacts, clipboard, and more when connected to an OpenClaw Gateway.
- **Agent Exploration**: View available models, providers, skills, memory, and cron jobs (read-only).
- **Settings & Configuration**: Configure server URL, authentication, default models, and clear cache.
- **Offline Support**: Read-only cache of sessions and messages via SwiftData.
- **Privacy-Focused**: No analytics or tracking; credentials stored securely in the Keychain.

## Architecture

The app follows a clean MVVM architecture with SwiftUI views and ObservableObject view models. Key layers include:

- **Presentation Layer**: SwiftUI views (Onboarding, SessionList, Chat, Settings, etc.)
- **Application Layer**: View models that manage state and coordinate with the backend.
- **Domain Layer**: Unified data models (`UnifiedSession`, `UnifiedMessage`, `UnifiedChatEvent`) that abstract differences between backends.
- **Data Layer**: 
  - `Backend` protocol defining the contract for Hermes and OpenClaw implementations.
  - `HermesBackend`: Implements the Hermes-webui API (REST + Server-Sent Events).
  - `OpenClawBackend`: Stub for OpenClaw Gateway API (to be implemented).
  - `APIClient`: A singleton `URLSession` wrapper with cookie handling.
  - `Persistence Layer`: SwiftData-based offline cache for sessions and messages.

## Dependencies

The project uses the following Swift Package Manager dependencies:

- [LDSwiftEventSource](https://github.com/leifd/LDSwiftEventSource) - For Server-Sent Events (Hermes)
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) - Markdown rendering
- [Splash](https://github.com/johnsundell/splash) & [Highlightr](https://github.com/raspu/Highlightr) - Syntax highlighting
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) - Secure storage for credentials

## Getting Started

### Prerequisites

- Xcode 15+ (for iOS 18+ SDK)
- iOS 18.0+ deployment target
- A running Hermes-webui server or OpenClaw Gateway for testing

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/DualAgent.git
   cd DualAgent
   ```

2. Fetch dependencies:
   ```bash
   # If using Swift Package Manager via Xcode, dependencies will resolve automatically.
   # Otherwise, you can run:
   swift package resolve
   ```

3. Open the project in Xcode:
   ```bash
   open DualAgent.xcodeproj
   ```

### Configuration

Before running the app, you need to configure the backend URLs:

1. For Hermes-webui: Set the base URL to your Hermes server (e.g., `https://hermes.example.com`).
2. For OpenClaw Gateway: Set the base URL to your OpenClaw gateway (e.g., `https://gateway.example.com`).

You can set these in the Onboarding screen when you first launch the app, or modify the default values in `AppConfig.swift`.

## Running the App

1. Select a target device (simulator or physical iOS device running iOS 18+).
2. Press `Cmd+R` in Xcode to build and run.

### Testing with Local Servers

#### Hermes-webui
- Run a local Hermes-webui instance (via Docker or `hermes server`).
- Use `http://localhost:8000` (or your chosen port) as the server URL in the app.
- Note: For local development, you may need to disable App Transport Security (ATS) or use HTTPS with a trusted certificate.

#### OpenClaw Gateway
- Follow the OpenClaw onboarding guide: `npx openclaw onboard` then `openclaw dashboard`.
- The gateway will typically run on `http://localhost:3000` or `https://localhost:3000`.
- Use the appropriate URL in the app.

## Project Structure

```
DualAgent/
├── DualAgentApp.swift          # App entry point
├── Config/
│   └── AppConfig.swift         # App-wide constants
├── Features/
│   ├── Chat/                   # Chat view and view model
│   ├── Onboarding/             # Onboarding flow
│   ├── SessionList/            # Session list view and view model
│   ├── Settings/               # Settings view and view model
│   ├── Workspace/              # File browser and preview
│   ├── Skills/                 # Skills catalog (read-only)
│   ├── Memory/                 # Memory and profile viewer (read-only)
│   ├── Tasks/                  # Cron jobs viewer (read-only)
│   ├── Insights/               # Usage analytics
│   └── Voice/                  # Voice talk mode (placeholder)
├── Models/                     # Unified data models
├── Networking/
│   ├── APIClient.swift         # Shared URLSession wrapper
│   ├── Backend.swift           # Backend protocol
│   ├── HermesBackend.swift     # Hermes-webui implementation
│   ├── OpenClawBackend.swift   # OpenClaw Gateway implementation (stub)
│   ├── APISelector.swift       # Runtime backend switcher (TODO)
│   ├── Endpoints.swift         # API endpoint definitions (TODO)
│   ├── SSEClient.swift         # Server-Sent Events client (TODO)
│   ├── WSClient.swift          # WebSocket client (TODO)
│   └── ChatStream.swift        # Chat stream parser (TODO)
├── Persistence/
│   ├── CacheStore.swift        # SwiftData stack
│   ├── CachedSession.swift     # Cached session model
│   └── CachedMessage.swift     # Cached message model
├── DesignSystem/               # Reusable UI components
└── Resources/                  # Asset catalog, Info.plist, etc.
```

## Backend Implementation Status

### HermesBackend
- ✅ Authentication (login/logout via HMAC cookie)
- ✅ Session management (list, create, delete, pin/archive)
- ✅ Chat initiation and control (start, steer, cancel)
- ✅ File upload (placeholder, needs multipart implementation)
- ✅ Model/provider/reasoning fetching
- ✅ Skills, memory, crons, workspace listing (read-only)
- ❌ File reading (text and raw) - needs implementation
- ❌ Real SSE chat stream (currently simulated)

### OpenClawBackend
- ❌ All methods are currently stubbed and return `notImplemented` errors.
- To implement, study the OpenClaw gateway API and map endpoints to the `Backend` protocol.

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'Add amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [Hermex](https://github.com/uzairansaruzi/hermex) and [OpenClaw](https://github.com/openclaw/openclaw).
- Thanks to the open-source community for the dependencies used.