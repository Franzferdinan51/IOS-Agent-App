import Foundation

/// URL factory for all backend endpoints.
///
/// Each backend type may have a different base path or query-parameter style,
/// so factory functions accept the backend base URL and return a fully-formed URL.
///
/// All path joining is done with `URL.appending(path:)` (which treats the new
/// path as a single path component and preserves slashes), NOT
/// `URL.appendingPathComponent("api/...")` which percent-encodes the slashes
/// and produces broken URLs like `https://host/api%2Fauth%2Flogin`.
enum Endpoints {

    // MARK: - Path joining

    /// Append a path to a base URL while preserving the slashes inside the
    /// added path. Falls back to the base URL if the join fails.
    private static func append(path: String, to baseURL: URL) -> URL {
        // Normalize: ensure the base ends without a trailing slash and the
        // path begins with one — then string-concatenate. This is the only
        // way to safely join URL paths with embedded slashes without the
        // percent-encoding that `appendingPathComponent` applies.
        let baseString = baseURL.absoluteString
        let trimmedBase = baseString.hasSuffix("/")
            ? String(baseString.dropLast())
            : baseString
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: trimmedBase + normalizedPath) ?? baseURL
    }

    /// Build a URL with query items.
    private static func withQuery(_ baseURL: URL, _ items: [URLQueryItem]) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url
    }

    // MARK: - Auth

    /// POST /api/auth/login
    static func login(baseURL: URL) -> URL {
        append(path: "api/auth/login", to: baseURL)
    }

    /// POST /api/auth/logout
    static func logout(baseURL: URL) -> URL {
        append(path: "api/auth/logout", to: baseURL)
    }

    // MARK: - Sessions

    /// GET /api/sessions
    static func sessions(baseURL: URL) -> URL {
        append(path: "api/sessions", to: baseURL)
    }

    /// POST /api/session/new
    static func createSession(baseURL: URL) -> URL {
        append(path: "api/session/new", to: baseURL)
    }

    /// POST /api/session/delete
    static func deleteSession(baseURL: URL) -> URL {
        append(path: "api/session/delete", to: baseURL)
    }

    /// POST /api/session/pin
    static func pinSession(baseURL: URL) -> URL {
        append(path: "api/session/pin", to: baseURL)
    }

    /// POST /api/session/unpin
    static func unpinSession(baseURL: URL) -> URL {
        append(path: "api/session/unpin", to: baseURL)
    }

    /// POST /api/session/archive
    static func archiveSession(baseURL: URL) -> URL {
        append(path: "api/session/archive", to: baseURL)
    }

    /// POST /api/session/unarchive
    static func unarchiveSession(baseURL: URL) -> URL {
        append(path: "api/session/unarchive", to: baseURL)
    }

    // MARK: - Chat

    /// POST /api/chat/start
    static func chatStart(baseURL: URL) -> URL {
        append(path: "api/chat/start", to: baseURL)
    }

    /// GET /api/chat/stream?stream_id=...
    static func chatStream(baseURL: URL, streamId: String) -> URL? {
        withQuery(append(path: "api/chat/stream", to: baseURL),
                  [URLQueryItem(name: "stream_id", value: streamId)])
    }

    /// WebSocket /api/chat/ws?stream_id=...
    static func chatWebSocket(baseURL: URL, streamId: String) -> URL? {
        let httpURL = append(path: "api/chat/ws", to: baseURL)
        var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false)
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
        append(path: "api/chat/steer", to: baseURL)
    }

    /// POST /api/chat/cancel
    /// (Per `hermex_spec_full.md §6.4` cancel is POST with a JSON body, not
    /// a GET with a query string.)
    static func chatCancel(baseURL: URL, streamId: String) -> URL? {
        withQuery(append(path: "api/chat/cancel", to: baseURL),
                  [URLQueryItem(name: "stream_id", value: streamId)])
    }

    // MARK: - Files

    /// POST /api/upload
    static func upload(baseURL: URL) -> URL {
        append(path: "api/upload", to: baseURL)
    }

    // MARK: - Workspace

    /// GET /api/list?session_id=...&path=...
    static func listWorkspace(baseURL: URL, sessionId: String, path: String) -> URL? {
        withQuery(append(path: "api/list", to: baseURL), [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path),
        ])
    }

    /// GET /api/file?session_id=...&path=...
    static func readFile(baseURL: URL, sessionId: String, path: String) -> URL? {
        withQuery(append(path: "api/file", to: baseURL), [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path),
        ])
    }

    /// GET /api/file/raw?session_id=...&path=...
    static func readFileRaw(baseURL: URL, sessionId: String, path: String) -> URL? {
        withQuery(append(path: "api/file/raw", to: baseURL), [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path),
        ])
    }

    // MARK: - Models / Providers / Reasoning

    /// GET /api/models
    static func models(baseURL: URL) -> URL {
        append(path: "api/models", to: baseURL)
    }

    /// GET /api/providers
    static func providers(baseURL: URL) -> URL {
        append(path: "api/providers", to: baseURL)
    }

    /// GET /api/reasoning
    static func reasoning(baseURL: URL) -> URL {
        append(path: "api/reasoning", to: baseURL)
    }

    /// POST /api/reasoning
    static func saveReasoning(baseURL: URL) -> URL {
        append(path: "api/reasoning", to: baseURL)
    }

    // MARK: - Skills

    /// GET /api/skills
    static func skills(baseURL: URL) -> URL {
        append(path: "api/skills", to: baseURL)
    }

    /// GET /api/skills/content?name=...
    static func skillContent(baseURL: URL, name: String) -> URL? {
        withQuery(append(path: "api/skills/content", to: baseURL),
                  [URLQueryItem(name: "name", value: name)])
    }

    // MARK: - Memory

    /// GET /api/memory
    static func memory(baseURL: URL) -> URL {
        append(path: "api/memory", to: baseURL)
    }

    // MARK: - Crons

    /// GET /api/crons
    static func crons(baseURL: URL) -> URL {
        append(path: "api/crons", to: baseURL)
    }

    /// GET /api/crons/output?job_id=...&limit=...
    static func cronOutput(baseURL: URL, jobId: String, limit: Int) -> URL? {
        withQuery(append(path: "api/crons/output", to: baseURL), [
            URLQueryItem(name: "job_id", value: jobId),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    // MARK: - Health

    /// GET /api/health
    static func health(baseURL: URL) -> URL {
        append(path: "api/health", to: baseURL)
    }
}