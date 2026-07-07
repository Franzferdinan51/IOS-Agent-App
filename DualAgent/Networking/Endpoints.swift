import Foundation

/// URL factory for all backend endpoints.
///
/// Each backend type may have a different base path or query-parameter style,
/// so factory functions accept the backend base URL and return a fully-formed URL.
enum Endpoints {

    // MARK: - Auth

    /// POST /api/auth/login
    static func login(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/auth/login")
    }

    /// POST /api/auth/logout
    static func logout(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/auth/logout")
    }

    // MARK: - Sessions

    /// GET /api/sessions
    static func sessions(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/sessions")
    }

    /// POST /api/session/new
    static func createSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/new")
    }

    /// POST /api/session/delete
    static func deleteSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/delete")
    }

    /// POST /api/session/pin
    static func pinSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/pin")
    }

    /// POST /api/session/unpin
    static func unpinSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/unpin")
    }

    /// POST /api/session/archive
    static func archiveSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/archive")
    }

    /// POST /api/session/unarchive
    static func unarchiveSession(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/session/unarchive")
    }

    // MARK: - Chat

    /// POST /api/chat/start
    static func chatStart(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/chat/start")
    }

    /// GET /api/chat/stream?stream_id=...
    static func chatStream(baseURL: URL, streamId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/chat/stream"),
                                      resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        return components?.url
    }

    /// WebSocket /api/chat/ws?stream_id=...
    static func chatWebSocket(baseURL: URL, streamId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/chat/ws"),
                                        resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        // Switch to ws:// or wss:// scheme
        if components?.scheme == "https" {
            components?.scheme = "wss"
        } else {
            components?.scheme = "ws"
        }
        return components?.url
    }

    /// POST /api/chat/steer
    static func chatSteer(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/chat/steer")
    }

    /// GET /api/chat/cancel?stream_id=...
    static func chatCancel(baseURL: URL, streamId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/chat/cancel"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        return components?.url
    }

    // MARK: - Files

    /// POST /api/upload
    static func upload(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/upload")
    }

    // MARK: - Workspace

    /// GET /api/list?session_id=...&path=...
    static func listWorkspace(baseURL: URL, sessionId: String, path: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/list"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        return components?.url
    }

    /// GET /api/file?session_id=...&path=...
    static func readFile(baseURL: URL, sessionId: String, path: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/file"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        return components?.url
    }

    /// GET /api/file/raw?session_id=...&path=...
    static func readFileRaw(baseURL: URL, sessionId: String, path: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/file/raw"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        return components?.url
    }

    // MARK: - Models / Providers / Reasoning

    /// GET /api/models
    static func models(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/models")
    }

    /// GET /api/providers
    static func providers(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/providers")
    }

    /// GET /api/reasoning
    static func reasoning(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/reasoning")
    }

    /// POST /api/reasoning
    static func saveReasoning(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/reasoning")
    }

    // MARK: - Skills

    /// GET /api/skills
    static func skills(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/skills")
    }

    /// GET /api/skills/content?name=...
    static func skillContent(baseURL: URL, name: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/skills/content"),
                                        resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        return components?.url
    }

    // MARK: - Memory

    /// GET /api/memory
    static func memory(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/memory")
    }

    // MARK: - Crons

    /// GET /api/crons
    static func crons(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/crons")
    }

    /// GET /api/crons/output?job_id=...&limit=...
    static func cronOutput(baseURL: URL, jobId: String, limit: Int) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/crons/output"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "job_id", value: jobId),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return components?.url
    }

    // MARK: - Health

    /// GET /api/health
    static func health(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/health")
    }
}
