//
//  WSClient.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// A WebSocket client for OpenClaw real-time communication.
@MainActor
final class WSClient: @unchecked Sendable {
    private var urlSessionWebSocketTask: URLSessionWebSocketTask?
    private var continuation: AsyncStream<WebSocketMessage>.Continuation?
    private let stream: AsyncStream<WebSocketMessage>
    private let urlSession: URLSession
    private var isConnected = false
    
    /// Creates a new WebSocket client that connects to the given URL.
    /// - Parameter url: The WebSocket URL to connect to.
    init(url: URL) {
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        
        stream = AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            
            // Create the WebSocket task
            let webSocketTask = urlSession.webSocketTask(with: url)
            self?.urlSessionWebSocketTask = webSocketTask
            
            // Start receiving messages
            self?.receiveMessage()
            
            // Connect
            webSocketTask.resume()
            self?.isConnected = true
            
            // Cleanup when the stream is cancelled
            continuation.onTermination = { [weak self] @Sendable _ in
                self?.disconnect()
            }
        }
    }
    
    /// The async stream of WebSocket messages.
    nonisolated var messages: AsyncStream<WebSocketMessage> {
        stream
    }
    
    /// Sends a message over the WebSocket connection.
    /// - Parameter message: The message to send.
    nonisolated func send(_ message: WebSocketMessage) async {
        guard let webSocketTask = urlSessionWebSocketTask, isConnected else { return }
        
        let wsMessage: URLSessionWebSocketTask.Message
        switch message {
        case .string(let text):
            wsMessage = .string(text)
        case .data(let data):
            wsMessage = .data(data)
        }
        
        await webSocketTask.send(wsMessage) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    /// Receives a message from the WebSocket connection.
    private func receiveMessage() {
        urlSessionWebSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Convert URLSessionWebSocketTask.Message to our WebSocketMessage
                let wsMessage: WebSocketMessage
                switch message {
                case .string(let text):
                    wsMessage = .string(text)
                case .data(let data):
                    wsMessage = .data(data)
                @unknown default:
                    wsMessage = .string("") // Empty string for unknown types
                }
                
                self?.continuation?.yield(wsMessage)
                
                // Continue receiving messages
                self?.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.continuation?.finish()
                self?.isConnected = false
            }
        }
    }
    
    /// Disconnects the WebSocket connection.
    nonisolated func disconnect() {
        urlSessionWebSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSessionWebSocketTask = nil
        continuation?.finish()
        continuation = nil
        isConnected = false
        
        // Invalidate the session to cancel any pending operations
        urlSession.invalidateAndCancel()
    }
    
    deinit {
        disconnect()
    }
}

/// Represents a WebSocket message.
enum WebSocketMessage: Sendable {
    case string(String)
    case data(Data)
}