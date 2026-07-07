//
//  Endpoints.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// Typed endpoint functions for making requests to the backend APIs.
enum Endpoints {
    // MARK: - Auth & Health
    
    /// GET /health
    static func healthCheck(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/health"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/auth/status
    static func authStatus(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/auth/status"))
        request.httpMethod = "GET"
        return request
    }
    
    /// POST /api/auth/login
    static func login(baseURL: URL, password: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    /// POST /api/auth/logout
    static func logout(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/auth/logout"))
        request.httpMethod = "POST"
        return request
    }
    
    // MARK: - Sessions
    
    /// GET /api/sessions
    static func fetchSessions(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/sessions"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/session?session_id=...&messages=1&msg_limit=50
    static func fetchSession(baseURL: URL, sessionId: String, messageLimit: Int = 50) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/session"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "messages", value: "1"),
            URLQueryItem(name: "msg_limit", value: String(messageLimit))
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/session"))
        request.httpMethod = "GET"
        return request
    }
    
    /// POST /api/session/new
    static func createSession(baseURL: URL, workspace: String, model: String, profile: String? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/session/new"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "workspace": workspace,
            "model": model
        ]
        if let profile = profile {
            body["profile"] = profile
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    /// POST /api/session/delete
    static func deleteSession(baseURL: URL, sessionId: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/session/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_id": sessionId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    /// POST /api/session/pin
    static func setSessionPinned(baseURL: URL, sessionId: String, pinned: Bool) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/session/pin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [
            "session_id": sessionId,
            "pinned": pinned
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    /// POST /api/session/archive
    static func setSessionArchived(baseURL: URL, sessionId: String, archived: Bool) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/session/archive"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [
            "session_id": sessionId,
            "archived": archived
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    // MARK: - Chat
    
    /// POST /api/chat/start
    static func startChat(baseURL: URL, sessionId: String, message: String, attachments: [ChatAttachment]? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat/start"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "session_id": sessionId,
            "message": message
        ]
        if let attachments = attachments, !attachments.isEmpty {
            // Convert attachments to the format expected by the API
            let attachmentDicts = attachments.map { attachment in
                [
                    "filename": attachment.filename,
                    "mime_type": attachment.mimeType,
                    "data": attachment.data.base64EncodedString(),
                    "is_image": attachment.isImage
                ]
            }
            body["attachments"] = attachmentDicts
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    /// GET /api/chat/stream?stream_id=...
    static func chatStream(baseURL: URL, streamId: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/chat/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "stream_id", value: streamId)
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/chat/stream"))
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }
    
    /// GET /api/chat/cancel?stream_id=...
    static func cancelChat(baseURL: URL, streamId: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat/cancel"))
        request.httpMethod = "GET"
        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "stream_id", value: streamId)
        ]
        request.url = components?.url
        return request
    }
    
    /// POST /api/chat/steer
    static func steerChat(baseURL: URL, sessionId: String, text: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/chat/steer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = [
            "session_id": sessionId,
            "text": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    // MARK: - Upload
    
    /// POST /api/upload
    static func uploadFile(baseURL: URL, sessionId: String, fileData: Data, filename: String, mimeType: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/upload"))
        request.httpMethod = "POST"
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        // Add session_id
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(sessionId)\r\n".data(using: .utf8)!)
        
        // Add file
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = data
        return request
    }
    
    // MARK: - Models & Providers
    
    /// GET /api/models
    static func fetchModels(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/models"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/providers
    static func fetchProviders(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/providers"))
        request.httpMethod = "GET"
        return request
    }
    
    // MARK: - Reasoning
    
    /// GET /api/reasoning
    static func fetchReasoning(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/reasoning"))
        request.httpMethod = "GET"
        return request
    }
    
    /// POST /api/reasoning
    static func saveReasoning(baseURL: URL, effort: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/reasoning"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["effort": effort]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    // MARK: - Skills
    
    /// GET /api/skills
    static func fetchSkills(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/skills"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/skills/content?name=...
    static func fetchSkillContent(baseURL: URL, name: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/skills/content"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: name)
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/skills/content"))
        request.httpMethod = "GET"
        return request
    }
    
    // MARK: - Memory
    
    /// GET /api/memory
    static func fetchMemory(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/memory"))
        request.httpMethod = "GET"
        return request
    }
    
    // MARK: - Crons
    
    /// GET /api/crons
    static func fetchCrons(baseURL: URL) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/crons"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/crons/output?job_id=...&limit=...
    static func fetchCronOutput(baseURL: URL, jobId: String, limit: Int = 100) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/crons/output"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "job_id", value: jobId),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/crons/output"))
        request.httpMethod = "GET"
        return request
    }
    
    // MARK: - Workspace/Files
    
    /// GET /api/list?session_id=...&path=...
    static func listWorkspace(baseURL: URL, sessionId: String, path: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/list"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/list"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/file?session_id=...&path=...
    static func readFile(baseURL: URL, sessionId: String, path: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/file"))
        request.httpMethod = "GET"
        return request
    }
    
    /// GET /api/file/raw?session_id=...&path=...
    static func readFileRaw(baseURL: URL, sessionId: String, path: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/file/raw"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/file/raw"))
        request.httpMethod = "GET"
        return request
    }
}

// MARK: - Response Models

/// Response for health check
struct HealthResponse: Decodable {
    let status: String
}

/// Response for auth status
struct AuthStatusResponse: Decodable {
    let auth_enabled: Bool
}

/// Response for login
struct LoginResponse: Decodable {
    let success: Bool
}

/// Response for sessions list
struct SessionsResponse: Decodable {
    let sessions: [UnifiedSession]
}

/// Response for single session
struct SessionResponse: Decodable {
    let session: UnifiedSession
}

/// Response for chat start
struct ChatStartResponse: Decodable {
    let stream_id: String
    let session_id: String
}

/// Response for upload
struct UploadResponse: Decodable {
    let filename: String
    let path: String
    let mime_type: String
    let size: Int
    let is_image: Bool
}

/// Response for models
struct ModelsResponse: Decodable {
    let models: [String]
}

/// Response for providers
struct ProvidersResponse: Decodable {
    let providers: [String]
}

/// Response for reasoning
struct ReasoningResponse: Decodable {
    let effort: String?
}

/// Response for skills
struct SkillsResponse: Decodable {
    let skills: [SkillSummary]
}

/// Response for skill content
struct SkillContentResponse: Decodable {
    let markdown: String
    let linked_files: [String: String]  // filename -> content
}

/// Response for memory
struct MemoryResponse: Decodable {
    let notes: String
    let profile: String
}

/// Response for crons
struct CronsResponse: Decodable {
    let cron_jobs: [CronJobSummary]
}

/// Response for cron output
struct CronOutputResponse: Decodable {
    let output: String
}

/// Response for workspace listing
struct WorkspaceResponse: Decodable {
    let entries: [WorkspaceEntry]
}

/// Response for file reading
struct FileResponse: Decodable {
    let content: String
    let mime_type: String
    let size: Int
}

/// Response for raw file reading
struct RawFileResponse: Decodable {
    let data: String  // Base64 encoded
    let mime_type: String
    let size: Int
}