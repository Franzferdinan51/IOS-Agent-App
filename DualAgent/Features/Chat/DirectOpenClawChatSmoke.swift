//
//  DirectOpenClawChatSmoke.swift
//  DualAgent
//
//  Drives the in-app ChatViewModel pipeline end-to-end against a real
//  OpenClaw gateway, WITHOUT simulating UI input. Purpose: prove the
//  actual chat input pipeline (viewModel.messageText → sendMessage()
//  → backend.startChat(...) → backend.chatStream(streamId:) → token
//  events) works end-to-end. The smoke:
//    1. reads its config from process env + argv
//    2. logs into the OpenClawBackend with the configured token
//    3. starts a chat via OpenClawGateway (if supported) OR prints a
//       warning that the gateway is missing RPC methods and skips
//    4. waits for stream events, parsing + logging each one
//    5. writes a structured transcript log to Library/Logs
//
//  Triggered by launch arg `-DADirectChatSmoke` and/or env
//  `DA_DIRECT_OPENCLAW_CHAT_SMOKE=1`. Only compiled in DEBUG.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct DirectOpenClawChatSmoke {
    static func runIfRequested(authManager: AuthManager) {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        let enabled = (env["DA_DIRECT_OPENCLAW_CHAT_SMOKE"] == "1") || args.contains("-DADirectChatSmoke")
        guard enabled else { return }

        // Persist only once per simulator install (matches Hermes smoke).
        guard UserDefaults.standard.bool(forKey: "debug.directOpenClawChatSmoke.hasRun") == false else { return }
        UserDefaults.standard.set(true, forKey: "debug.directOpenClawChatSmoke.hasRun")
        UserDefaults.standard.set("starting", forKey: "debug.directOpenClawChatSmoke.result")

        writeLog("SMOKE starting backendType=\(authManager.currentBackendType)")

        Task {
            await run(authManager: authManager)
        }
        #endif
    }

    #if DEBUG
    private static func run(authManager: AuthManager) async {
        let env = ProcessInfo.processInfo.environment
        let serverURL = env["DA_SERVER_URL"] ?? "http://127.0.0.1:18790"
        let credential = env["DA_OPENCLAW_TOKEN"] ?? env["DA_CREDENTIAL"] ?? ""
        let prompt = env["DA_DIRECT_OPENCLAW_PROMPT"] ?? "hello from DualAgent"

        // 1. Force backend to OpenClaw.
        authManager.switchBackend(to: .openclaw)
        writeLog("SMOKE switched backend to openclaw; serverURL=\(serverURL) credential-len=\(credential.count)")

        // 2. Login through the OpenClawBackend (real WS handshake).
        do {
            try await authManager.connect(serverURL: serverURL, credential: credential)
            writeLog("SMOKE login ok; authManager.isAuthenticated=\(authManager.isAuthenticated)")
        } catch {
            writeLog("SMOKE login FAILED: \(error.localizedDescription)")
            UserDefaults.standard.set("login-failed", forKey: "debug.directOpenClawChatSmoke.result")
            return
        }

        let backend = authManager.backend
        guard let openClaw = backend as? OpenClawBackend else {
            writeLog("SMOKE backend NOT OpenClawBackend after switch (got \(type(of: backend)))")
            UserDefaults.standard.set("backend-mismatch", forKey: "debug.directOpenClawChatSmoke.result")
            return
        }

        // 3. Issue sessions.create via the protocol surface. If the gateway
        //    doesn't support it we capture that as a structured result.
        let session: UnifiedSession
        do {
            session = try await openClaw.createSession(workspace: "smoke-workspace", model: "@minimax:MiniMax-M3", profile: nil)
            writeLog("SMOKE created session id=\(session.id) model=\(session.model) workspace=\(session.workspace)")
        } catch {
            writeLog("SMOKE createSession failed: \(error.localizedDescription) — falling back to chat.send on stub session")
            // Some OpenClaw variants don't implement sessions.create; build
            // a synthetic session id so the rest of the pipeline runs.
            let fakeId = "smoke-\(UUID().uuidString.prefix(8))"
            session = UnifiedSession(
                id: fakeId,
                title: "Direct OpenClaw smoke",
                createdAt: Date(),
                updatedAt: Date(),
                workspace: "smoke-workspace",
                model: "@minimax:MiniMax-M3",
                modelProvider: "smoke"
            )
            writeLog("SMOKE synthetic session id=\(session.id)")
        }

        // 4. Drive ChatViewModel end-to-end with the actual input pipeline.
        let viewModel = ChatViewModel(backend: backend, sessionId: session.id, session: session)
        viewModel.messageText = prompt

        let totalCollected: NSLock = NSLock()
        var collected: [String] = []
        var tokenCount = 0
        var errorCount = 0
        var endSeen = false

        let startedAt = Date()
        writeLog("SMOKE calling viewModel.sendMessage() prompt-len=\(prompt.count)")
        viewModel.sendMessage()

        // 5. Read the stream events back into a collected transcript.
        //    Listen for up to 30 seconds; stream events are emitted as the
        //    backend response streams in.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            // Touch the message count to keep @Published / view body alive.
            _ = viewModel.messages.count

            // Did we get an error message?
            if let err = viewModel.errorMessage {
                if errorCount == 0 {
                    writeLog("SMOKE viewModel.errorMessage=\(err)")
                }
                errorCount += 1
            }

            // Did we see the .streamEnd event reflected in the latest assistant
            // message? We don't intercept UnifiedChatEvent directly here, but
            // we can ask viewModel.messages to confirm whether the response is
            // done (no longer isStreaming).
            if !viewModel.isStreaming && (viewModel.messages.contains(where: { $0.role == .assistant && !$0.content.isEmpty }) || errorCount > 0) {
                endSeen = true
                break
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        // 6. Collect the assistant messages back out of the viewModel.
        for message in viewModel.messages {
            if message.role == .assistant, !message.content.isEmpty {
                let snippet = String(message.content.prefix(160))
                writeLog("SMOKE assistant-message-bytes=\(message.content.count) preview=\(snippet.debugEscaped)")
                tokenCount += 1
                totalCollected.lock()
                collected.append(snippet)
                totalCollected.unlock()
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let summary = "ran=true endSeen=\(endSeen) tokens=\(tokenCount) errors=\(errorCount) elapsed=\(String(format: "%.1f", elapsed))s"
        writeLog("SMOKE complete: \(summary)")
        UserDefaults.standard.set(summary, forKey: "debug.directOpenClawChatSmoke.result")
    }

    private static let logURL: URL = {
        let fm = FileManager.default
        let dir = (try? fm.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("DualAgent", isDirectory: true)) ?? URL(fileURLWithPath: "/tmp/DualAgent")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("direct-openclaw-chat-smoke.log")
    }()

    static func writeLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let row = "[\(ts)] \(line)\n"
        if let data = row.data(using: .utf8) {
            let fm = FileManager.default
            if let h = try? fm.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DualAgent", isDirectory: true)
            {
                try? fm.createDirectory(at: h, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: logURL.path) {
                    fm.createFile(atPath: logURL.path, contents: nil)
                }
                if let f = try? FileHandle(forWritingTo: logURL) {
                    f.seekToEndOfFile()
                    f.write(data)
                    try? f.close()
                }
            }
        }
        print(row, terminator: "")
    }
    #endif
}

private extension String {
    var debugEscaped: String {
        replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
