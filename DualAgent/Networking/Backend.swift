import Foundation

/// A protocol that abstracts the backend-specific API calls for either Hermes‑webui or OpenClaw Gateway.
protocol Backend {
    /// The base URL of the backend server.
    var baseURL: URL { get }
    
    /// The authentication status.
    var isAuthenticated: Bool { get }
    
    /// Log in to the backend.
    /// - Parameters:
    ///   - credentials: Username/password or token, depending on backend.
    /// - Returns: True if login succeeded.
    func login(credentials: [String: String]) async throws -> Bool
    
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

/// Represents a chat attachment (file or image) to be sent with a message.
struct ChatAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let isImage: Bool
}

/// Result of a file upload.
struct UploadResult {
    let filename: String
    let path: String
    let mimeType: String
    let size: Int
    let isImage: Bool
}

/// Summary of a session.
struct UnifiedSession: Identifiable, Codable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?
    let isPinned: Bool
    let isArchived: Bool
    let projectId: String?
    let workspace: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCost: Double
}

/// Summary of a skill.
struct SkillSummary: Identifiable, Codable {
    let name: String
    let category: String
    let description: String
}

/// Content of a skill.
struct SkillContent {
    let markdown: String
    let linkedFiles: [String: String]  // filename -> content
}

/// Summary of a cron job / scheduled task.
struct CronJobSummary: Identifiable, Codable {
    let id: String
    let name: String
    let schedule: String
    let nextRun: Date?
    let lastRun: Date?
    let isRunning: Bool
    let prompt: String
    let skill: String?
}

/// Result of reading a file.
struct FileResult {
    let content: String
    let mimeType: String
    let size: Int
}

/// Result of reading a file as raw data.
struct RawFileResult {
    let data: Data
    let mimeType: String
    let size: Int
}

/// Represents a workspace entry (file or folder).
struct WorkspaceEntry: Identifiable, Codable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
    let modifiedAt: Date?
}