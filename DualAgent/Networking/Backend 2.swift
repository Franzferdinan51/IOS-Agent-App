import Foundation

/// Protocol defining the backend agnostic API for the DualAgent app.
/// Each concrete backend (Hermes, OpenClaw) must implement this protocol.
protocol Backend {
    /// The base URL of the server (e.g., https://hermes.example.com or https://opencv.example.com)
    var baseURL: URL { get }
    
    /// The authentication token or credential stored securely (if any).
    /// This is used by the APIClient to attach to requests.
    var authToken: String? { get }
    
    /// Log in with the provided credentials.
    /// - Parameters:
    ///   - usernameOrEmail: For Hermes, this is ignored (password only). For OpenClaw, could be username or email.
    ///   - passwordOrAPIKey: For Hermes, this is the password. For OpenClaw, this could be an API key or password.
    /// - Returns: True if login was successful.
    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool
    
    /// Log out and clear any stored credentials.
    func logout()
    
    /// Test the connection to the server (e.g., ping or health endpoint).
    /// - Returns: True if the server is reachable and responding.
    func testConnection() async throws -> Bool
    
    // MARK: - Session Management
    
    /// Get a list of sessions.
    /// - Returns: An array of session summaries.
    func getSessions() async throws -> [UnifiedSession]
    
    /// Create a new session.
    /// - Parameters:
    ///   - workspace: The workspace to use for the session.
    ///   - model: The model ID to use.
    ///   - provider: The provider (optional for Hermes, required for OpenClaw?).
    ///   - profile: The profile to use (optional).
    /// - Returns: The newly created session.
    func createSession(workspace: String, model: String, provider: String?, profile: String?) async throws -> UnifiedSession
    
    /// Get a session with its messages.
    /// - Parameters:
    ///   - sessionID: The ID of the session.
    ///   - messageLimit: The maximum number of messages to retrieve (most recent).
    /// - Returns: The session with messages.
    func getSession(sessionID: String, messageLimit: Int) async throws -> UnifiedSession

    /// Delete a session.
    /// - Parameter sessionID: The ID of the session to delete.
    func deleteSession(sessionID: String) async throws

    /// Toggle the pin state of a session.
    /// - Parameter sessionID: The ID of the session to toggle.
    func togglePin(sessionID: String) async throws

    /// Toggle the archive state of a session.
    /// - Parameter sessionID: The ID of the session to toggle.
    func toggleArchive(sessionID: String) async throws
    
    // MARK: - Chat
    
    /// Start a chat session and return a stream ID and the initial response.
    /// - Parameters:
    ///   - sessionID: The ID of the session to chat in.
    ///   - message: The user's message.
    ///   - attachments: Optional array of attachments (file data, filename, mime type).
    /// - Returns: A tuple of (streamID, initialResponse) where initialResponse may contain the first part of the response.
    func startChat(sessionID: String, message: String, attachments: [Attachment]?) async throws -> (streamID: String, initialResponse: String?)
    
    /// Connect to the chat stream for a given stream ID.
    /// - Parameter streamID: The ID of the stream to connect to.
    /// - Returns: An asynchronous sequence of chat events.
    func chatStream(streamID: String) -> AsyncThrowingStream<UnifiedChatEvent, Error>
    
    /// Cancel an ongoing chat stream.
    /// - Parameter streamID: The ID of the stream to cancel.
    func cancelChat(streamID: String) async throws
    
    // MARK: - File Operations
    
    /// Upload a file as an attachment.
    /// - Parameters:
    ///   - sessionID: The session to associate the attachment with.
    ///   - fileData: The data of the file.
    ///   - filename: The name of the file.
    ///   - mimeType: The MIME type of the file.
    /// - Returns: Metadata about the uploaded file.
    func uploadFile(sessionID: String, fileData: Data, filename: String, mimeType: String) async throws -> FileMetadata
    
    // MARK: - Workspace / File System
    
    /// Get a list of workspace roots (for Hermes) or filesystem roots (for OpenClaw).
    func getWorkspaces() async throws -> [WorkspaceEntry]
    
    /// Get the contents of a directory in the workspace.
    /// - Parameters:
    ///   - workspaceID: The ID or path of the workspace.
    ///   - path: The path within the workspace (relative to the root).
    /// - Returns: The directory listing.
    func listDirectory(workspaceID: String, path: String) async throws -> [FileItem]
    
    /// Read a file from the workspace.
    /// - Parameters:
    ///   - workspaceID: The ID or path of the workspace.
    ///   - filePath: The path of the file within the workspace.
    ///   - raw: If true, return the raw bytes (for images, etc.); if false, return as text (for text files).
    /// - Returns: The file data and metadata.
    func readFile(workspaceID: String, filePath: String, raw: Bool) async throws -> FileData
    
    // MARK: - Skills, Memory, Cron (Read-Only in v1)
    
    /// Get a list of available skills.
    func getSkills() async throws -> [Skill]
    
    /// Get the content of a specific skill.
    /// - Parameter skillName: The name of the skill.
    /// - Returns: The skill's markdown content and any linked files.
    func getSkillContent(name: String) async throws -> SkillContent
    
    /// Get memory notes and user profile.
    func getMemory() async throws -> MemoryData
    
    /// Get a list of scheduled jobs (cron/tasks).
    func getJobs() async throws -> [Job]
    
    // MARK: - Models, Providers, Profiles, Reasoning
    
    /// Get a list of available models.
    func getModels() async throws -> [ModelInfo]
    
    /// Get a list of available providers.
    func getProviders() async throws -> [ProviderInfo]
    
    /// Get a list of available profiles.
    func getProfiles() async throws -> [ProfileInfo]
    
    /// Get the available reasoning effort levels.
    func getReasoningOptions() async throws -> [ReasoningOption]
    
    // MARK: - Settings
    
    /// Get general server settings (e.g., version, bot name).
    func getSettings() async throws -> ServerSettings
}

/// A simple wrapper for file metadata returned by upload endpoints.
struct FileMetadata: Codable {
    let filename: String
    let path: String
    let mimeType: String
    let size: Int
    let isImage: Bool
}

/// A wrapper for file data returned by read endpoints.
struct FileData {
    let data: Data
    let mimeType: String
    let suggestedFilename: String
}

/// A workspace or filesystem entry.
struct WorkspaceEntry: Identifiable, Codable {
    let id: String
    let name: String
    let isDirectory: Bool
}

/// A file or directory item in a listing.
struct FileItem: Identifiable, Codable {
    let id: String
    let name: String
    let isDirectory: Bool
    let size: Int?
    let modifiedDate: Date?
}

/// A skill (for the skills catalog).
struct Skill: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let category: String
}

/// The content of a skill (markdown and linked files).
struct SkillContent: Codable {
    let name: String
    let markdown: String
    let files: [String: String]  // filename -> content (text)
}

/// Memory data (notes and user profile).
struct MemoryData: Codable {
    let notes: [String]
    let userProfile: [String: String]  // key-value pairs
}

/// A scheduled job or task.
struct Job: Identifiable, Codable {
    let id: String
    let name: String
    let status: String  // e.g., "idle", "running", "completed", "failed"
    let createdAt: Date
    /// Additional job-specific data can be stored here.
    let metadata: [String: String]
}

/// Information about a model.
struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let provider: String
    /// Optional: the context length, etc.
    let contextLength: Int?
}

/// Information about a provider (e.g., openai, anthropic, local).
struct ProviderInfo: Identifiable, Codable {
    let id: String
    let name: String
}

/// Information about a profile (a set of settings for the agent).
struct ProfileInfo: Identifiable, Codable {
    let id: String
    let name: String
}

/// Reasoning effort options (for Hermes).
struct ReasoningOption: Identifiable, Codable {
    let id: String  // e.g., "low", "medium", "high"
    let name: String
    let description: String
}

/// Server settings (version, etc.).
struct ServerSettings: Codable {
    let version: String
    let botName: String
    /// Any other arbitrary settings.
    let extra: [String: String]
}