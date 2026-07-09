import Foundation

/// The type of backend.
enum BackendType {
    case hermes
    case openclaw
}

/// A protocol that abstracts the backend-specific API calls for either Hermes‑webui or OpenClaw Gateway.
protocol Backend {
    /// The type of the backend.
    var backendType: BackendType { get }
    
    /// The base URL of the backend server.
    var baseURL: URL { get }
    
    /// The authentication status.
    var isAuthenticated: Bool { get }
    
    /// Log in to the backend.
    /// - Parameter credential: The single credential for the selected backend:
    ///   - Hermes: the server password (POSTed to `/api/auth/login`).
    ///   - OpenClaw: the gateway token (sent as `Authorization: Bearer …`).
    /// - Returns: True if login succeeded.
    func login(credential: String) async throws -> Bool
    
    /// Log out from the backend.
    func logout() async throws
    
    /// Fetch the list of sessions.
    /// - Returns: An array of session summaries.
    func fetchSessions() async throws -> [UnifiedSession]
    
    /// Create a new session.
    /// - Parameters:
    ///   - workspace: The workspace ID or path.
    ///   - model: The model identifier.
    ///   - profile: Optional profile identifier.
    /// - Returns: The created session.
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession
    
    /// Delete a session.
    /// - Parameter sessionId: The ID of the session to delete.
    func deleteSession(sessionId: String) async throws
    
    /// Pin or unpin a session.
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - pinned: Whether to pin (true) or unpin (false).
    func setSessionPinned(sessionId: String, pinned: Bool) async throws
    
    /// Archive or unarchive a session.
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - archived: Whether to archive (true) or unarchive (false).
    func setSessionArchived(sessionId: String, archived: Bool) async throws
    
    /// Start a chat session with a message.
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - message: The user message.
    ///   - attachments: Optional array of attachment data.
    /// - Returns: A stream ID or identifier for the chat stream.
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String
    
    /// Send a steer command to an active chat.
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - text: The steer text.
    /// - Returns: Whether the steer was accepted.
    func steerChat(sessionId: String, text: String) async throws -> Bool
    
    /// Cancel an active chat stream.
    /// - Parameter streamId: The ID of the stream to cancel.
    func cancelChat(streamId: String) async throws

    /// Subscribe to a chat stream's events.
    /// - Parameter streamId: The ID of the stream to listen to.
    /// - Returns: An async stream of chat events for this stream.
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error>

    /// Upload a file for attachment.
    /// - Parameters:
    ///   - sessionId: The session ID to associate the upload with.
    ///   - fileData: The file data.
    ///   - filename: The original filename.
    ///   - mimeType: The MIME type of the file.
    /// - Returns: Upload metadata (filename, path, etc.).
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult
    
    /// Fetch the list of available models.
    /// - Returns: An array of model identifiers.
    func fetchModels() async throws -> [String]
    
    /// Fetch the list of available providers.
    /// - Returns: An array of provider identifiers.
    func fetchProviders() async throws -> [String]

    /// Fetch the backend's default workspace for new sessions, if available.
    /// - Returns: A server-resolved workspace path or nil when the backend does not expose one.
    func fetchDefaultWorkspace() async throws -> String?
    
    /// Fetch the current reasoning setting.
    /// - Returns: The reasoning effort or setting.
    func fetchReasoning() async throws -> String?
    
    /// Save the reasoning setting.
    /// - Parameter effort: The reasoning effort to save.
    func saveReasoning(effort: String) async throws
    
    /// Fetch the list of skills.
    /// - Returns: An array of skill summaries.
    func fetchSkills() async throws -> [SkillSummary]
    
    /// Fetch the content of a specific skill.
    /// - Parameter name: The name of the skill.
    /// - Returns: The skill content (markdown) and optional linked files.
    func fetchSkillContent(name: String) async throws -> SkillContent
    
    /// Fetch memory notes and user profile.
    /// - Returns: A tuple of (memoryNotes, userProfile).
    func fetchMemory() async throws -> (String, String)
    
    /// Fetch the list of cron jobs / scheduled tasks.
    /// - Returns: An array of cron job summaries.
    func fetchCrons() async throws -> [CronJobSummary]
    
    /// Fetch the output of a specific cron job.
    /// - Parameters:
    ///   - jobId: The ID of the cron job.
    ///   - limit: Maximum number of output lines to return.
    /// - Returns: The job output.
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String

    /// Manually trigger a cron job now. Returns a `runId` callers can
    /// poll via `fetchCronOutput` to retrieve output as it streams.
    /// - Parameter jobId: The ID of the cron job to run.
    /// - Returns: The new run id, or `nil` if the backend does not support
    ///   manual cron execution (Hermes currently returns nil).
    func runCronNow(jobId: String) async throws -> String?
    
    /// Fetch the workspace/file listing for a given path.
    /// - Parameters:
    ///   - sessionId: The session ID (for context, if needed).
    ///   - path: The path to list.
    /// - Returns: An array of file/folder entries.
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry]
    
    /// Read a file from the workspace.
    /// - Parameters:
    ///   - sessionId: The session ID (for context, if needed).
    ///   - path: The path to the file.
    /// - Returns: The file content and metadata.
    func readFile(sessionId: String, path: String) async throws -> FileResult
    
    /// Read a file as raw data (for images/binaries).
    /// - Parameters:
    ///   - sessionId: The session ID (for context, if needed).
    ///   - path: The path to the file.
    /// - Returns: The raw file data and metadata.
    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult
}