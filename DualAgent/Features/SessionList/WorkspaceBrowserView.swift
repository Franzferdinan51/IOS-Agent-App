//
//  FileBrowserView.swift
//  DualAgent
//
//  Read-only browser for a session's workspace files. Backed by the
//  unified `Backend.listWorkspace` / `readFile` / `readFileRaw` surface
//  which both Hermes (`/api/list`, `/api/file`) and OpenClaw
//  (`sessions.files.list`, `sessions.files.get`) implement.
//
//  `FilePreviewSheet` is backend-neutral: it fetches text via
//  `readFile()` and falls back to `readFileRaw()` for binary payloads.
//  Rendering is selected from the file's mime type and extension:
//  - image/{png,jpeg,gif,heic,webp}      → Image(uiImage:)
//  - application/pdf                      → PDFKit PDFView
//  - .md / .markdown (text/markdown)      → MarkdownUI
//  - known code extensions                → Highlightr
//  - other binary                         → placeholder with size + mime
//

import SwiftUI
import PDFKit
import MarkdownUI
import Highlightr

// MARK: - File type classification

/// How a workspace file should be rendered in the preview sheet.
enum PreviewKind: Equatable {
    case image(mime: String)
    case pdf
    case markdown
    case code(language: String?)
    case text
    case binary(mime: String)
}

/// Extensions whose contents we can hand to Highlightr.
private let codeLanguageByExtension: [String: String] = [
    "swift": "swift",
    "m": "objectivec",
    "mm": "objectivec",
    "h": "objectivec",
    "c": "c",
    "cc": "cpp",
    "cpp": "cpp",
    "hpp": "cpp",
    "js": "javascript",
    "mjs": "javascript",
    "cjs": "javascript",
    "jsx": "javascript",
    "ts": "typescript",
    "tsx": "typescript",
    "py": "python",
    "rb": "ruby",
    "go": "go",
    "rs": "rust",
    "java": "java",
    "kt": "kotlin",
    "kts": "kotlin",
    "sh": "bash",
    "bash": "bash",
    "zsh": "bash",
    "php": "php",
    "cs": "csharp",
    "sql": "sql",
    "html": "xml",
    "htm": "xml",
    "xml": "xml",
    "css": "css",
    "scss": "scss",
    "less": "less",
    "json": "json",
    "yaml": "yaml",
    "yml": "yaml",
    "toml": "ini",
    "ini": "ini",
    "conf": "ini",
    "lua": "lua",
    "pl": "perl",
    "r": "r",
    "scala": "scala",
    "dart": "dart",
    "ex": "elixir",
    "exs": "elixir",
    "clj": "clojure",
    "hs": "haskell",
    "vue": "xml",
    "svelte": "xml",
    "graphql": "graphql",
    "proto": "protobuf",
    "dockerfile": "dockerfile",
]

/// Treat these mime types as binary for preview selection, regardless of
/// what the gateway claims. Image/PDF markdown have their own kinds.
private let binaryMimePrefixes: [String] = [
    "application/octet-stream",
    "application/zip",
    "application/x-tar",
    "application/x-gzip",
    "application/x-bzip2",
    "application/x-7z-compressed",
    "application/x-rar-compressed",
    "application/x-apple-diskimage",
    "audio/",
    "video/",
    "font/",
]

/// Returns a `PreviewKind` for the given file + metadata.
func classifyPreview(filename: String, mimeType: String, sizeBytes: Int64?) -> PreviewKind {
    let lowerName = filename.lowercased()
    let ext = (lowerName as NSString).pathExtension

    // 1. Markdown wins before generic text even if backend returned text/plain.
    if ext == "md" || ext == "markdown" || mimeType == "text/markdown" {
        return .markdown
    }

    // 2. Images — match by mime, fall back to extension.
    if mimeType.hasPrefix("image/") {
        // Be permissive on extension too for HEIC/HEIF which sometimes arrive
        // as application/octet-stream on some servers.
        let known = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]
        if known.contains(ext) || ["png", "jpeg", "gif", "webp"].contains(where: { mimeType.contains($0) }) {
            return .image(mime: mimeType)
        }
    }
    if ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp"].contains(ext) {
        return .image(mime: mimeType)
    }

    // 3. PDF.
    if mimeType == "application/pdf" || ext == "pdf" {
        return .pdf
    }

    // 4. Known code extensions.
    if let lang = codeLanguageByExtension[ext] {
        return .code(language: lang)
    }

    // 5. Plain text only when the backend says so.
    if mimeType.hasPrefix("text/") || mimeType == "application/json" {
        return .text
    }

    // 6. Known binary prefixes.
    if binaryMimePrefixes.contains(where: { mimeType.hasPrefix($0) }) {
        return .binary(mime: mimeType)
    }

    // 7. Heuristic: very small files are usually safe to render as text even
    //    when mime isn't set; only do that when there's some size signal.
    if let size = sizeBytes, size < 256 * 1024, mimeType.isEmpty {
        return .text
    }

    return .binary(mime: mimeType)
}

// MARK: - Highlighter singleton

/// Global Highlightr instance — creating a `Highlightr` is expensive enough
/// that we keep one for the lifetime of the preview sheet. The initializer
/// is failable (it needs a working JSContext), so we hold an Optional and
/// fall back to a plain monospaced `Text` when JSContext setup failed.
private final class HighlightHolder {
    static let shared: Highlightr? = {
        guard let h = Highlightr() else { return nil }
        // Best-effort theme; if "atom-one-dark" isn't bundled we fall back
        // to whatever default Highlightr ships.
        _ = h.setTheme(to: "atom-one-dark")
        return h
    }()
}

// MARK: - FileBrowserView (directory listing)

struct FileBrowserView: View {
    let sessionId: String
    let sessionTitle: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @State private var path: String = ""
    @State private var entries: [WorkspaceEntry] = []
    @State private var selectedFile: WorkspaceEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        navigateUp()
                    } label: {
                        Label("Go up", systemImage: "arrow.up")
                    }
                    .disabled(path.isEmpty)

                    if entries.isEmpty {
                        if isLoading {
                            ProgressView("Loading \(path.isEmpty ? "/" : path)…")
                        } else if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        } else {
                            Text("Empty directory.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                if entry.isDirectory {
                                    navigateInto(entry)
                                } else {
                                    selectedFile = entry
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.isDirectory ? "folder.fill" : rowIcon(for: entry))
                                        .foregroundStyle(entry.isDirectory ? brand.secondary : brand.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .foregroundStyle(.primary)
                                        if let size = entry.size {
                                            Text(formatBytes(size))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: entry.isDirectory ? "chevron.right" : "eye")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text(path.isEmpty ? "/" : path)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedFile) { file in
                FilePreviewSheet(sessionId: sessionId, file: file)
                    .environment(\.brand, brand)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await AuthManager.shared.backend.listWorkspace(
                sessionId: sessionId,
                path: path
            )
        } catch {
            errorMessage = "Couldn't load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func navigateInto(_ entry: WorkspaceEntry) {
        path = path.isEmpty ? entry.name : "\(path)/\(entry.name)"
        Task { await load() }
    }

    private func navigateUp() {
        let parts = path.split(separator: "/").map(String.init)
        if !parts.isEmpty {
            path = parts.dropLast().joined(separator: "/")
            Task { await load() }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func rowIcon(for entry: WorkspaceEntry) -> String {
        let kind = classifyPreview(filename: entry.name, mimeType: "", sizeBytes: entry.size)
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .markdown: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .binary: return "doc.zipper"
        }
    }
}

// MARK: - FilePreviewSheet (binary + text rendering)

/// Backend-neutral preview sheet that selects a renderer from the file's
/// mime type and extension. `readFile()` is tried first (cheap for text);
/// `readFileRaw()` is used for binaries and as a fallback when the text
/// endpoint refuses to return non-text payloads.
struct FilePreviewSheet: View {
    let sessionId: String
    let file: WorkspaceEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand

    @State private var phase: LoadPhase = .loading
    @State private var textContent: String = ""
    @State private var rawData: Data = Data()
    @State private var mimeType: String = ""
    @State private var errorMessage: String?

    /// Identifies which render path we're using — set as soon as the file
    /// has been classified from the first server response.
    @State private var kind: PreviewKind = .text

    enum LoadPhase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading \(file.name)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let msg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(Theme.error)
                        Text(msg)
                            .foregroundStyle(Theme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                case .ready:
                    previewBody
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task {
            await load()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") {
                dismiss()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                copyToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(!canCopy)
        }
    }

    private var canCopy: Bool {
        switch kind {
        case .text, .markdown, .code:
            return !textContent.isEmpty
        default:
            return false
        }
    }

    private func copyToClipboard() {
        guard !textContent.isEmpty else { return }
        UIPasteboard.general.string = textContent
        Haptic.tap()
    }

    // MARK: Routing by kind

    @ViewBuilder
    private var previewBody: some View {
        switch kind {
        case .image:
            ImagePreview(data: rawData)
        case .pdf:
            PDFPreview(data: rawData)
        case .markdown:
            MarkdownPreview(text: textContent)
        case .code(let language):
            CodePreview(text: textContent, language: language)
        case .text:
            TextPreview(text: textContent)
        case .binary(let mime):
            BinaryPreview(
                filename: file.name,
                mime: mime.isEmpty ? "application/octet-stream" : mime,
                sizeBytes: Int64(rawData.count)
            )
        }
    }

    // MARK: Loading

    private func load() async {
        phase = .loading
        errorMessage = nil

        let backend = AuthManager.shared.backend

        // Step 1 — always try the cheap text endpoint first so we can
        // classify the file from a real mime type when the server sets one.
        var firstMime = ""
        var firstSize: Int64 = 0
        var text: String?
        do {
            let result = try await backend.readFile(sessionId: sessionId, path: file.path)
            firstMime = result.mimeType
            firstSize = result.size
            text = result.content
        } catch {
            text = nil
        }

        // Classify using server mime when available; fall back to ext.
        let resolvedKind = classifyPreview(
            filename: file.name,
            mimeType: firstMime,
            sizeBytes: firstSize > 0 ? firstSize : file.size
        )
        kind = resolvedKind

        switch resolvedKind {
        case .text, .markdown, .code:
            if let text {
                textContent = text
                phase = .ready
                return
            }
            // Backend refused the text endpoint (binary-only file perhaps);
            // fall through to raw and decode UTF-8 if possible.
            await loadRawThenDecodeAsText(initialMime: firstMime)
        case .image, .pdf:
            await loadRaw(mimeHint: firstMime)
        case .binary:
            await loadRaw(mimeHint: firstMime)
        }
    }

    /// Fallback path: hit the raw endpoint and try UTF-8 decoding the bytes.
    /// Used when the text endpoint declined to return content but the
    /// resulting preview kind ended up being text-like.
    private func loadRawThenDecodeAsText(initialMime: String) async {
        let backend = AuthManager.shared.backend
        do {
            let raw = try await backend.readFileRaw(sessionId: sessionId, path: file.path)
            rawData = raw.data
            mimeType = raw.mimeType.isEmpty ? initialMime : raw.mimeType
            // Re-classify with the real mime in case it changed.
            kind = classifyPreview(
                filename: file.name,
                mimeType: mimeType,
                sizeBytes: Int64(raw.data.count)
            )
            switch kind {
            case .text, .markdown, .code:
                textContent = String(data: raw.data, encoding: .utf8)
                    ?? String(data: raw.data, encoding: .isoLatin1)
                    ?? ""
                phase = textContent.isEmpty
                    ? .failed("Couldn't decode file as text.")
                    : .ready
            case .image, .pdf, .binary:
                phase = .ready
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Fallback path for binaries: hit the raw endpoint and stage the bytes.
    private func loadRaw(mimeHint: String) async {
        let backend = AuthManager.shared.backend
        do {
            let raw = try await backend.readFileRaw(sessionId: sessionId, path: file.path)
            rawData = raw.data
            mimeType = raw.mimeType.isEmpty
                ? (mimeHint.isEmpty ? "application/octet-stream" : mimeHint)
                : raw.mimeType
            // Re-classify in case the raw response revealed a real mime type.
            kind = classifyPreview(
                filename: file.name,
                mimeType: mimeType,
                sizeBytes: Int64(raw.data.count)
            )
            if case .binary = kind {
                // already correct
            } else if case .text = kind,
                      let decoded = String(data: raw.data, encoding: .utf8)
                                ?? String(data: raw.data, encoding: .isoLatin1) {
                textContent = decoded
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Image preview

private struct ImagePreview: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .accessibilityLabel("Image preview")
                }
                .background(Color.black.opacity(0.04))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Couldn't decode image data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            image = UIImage(data: data)
        }
    }
}

// MARK: - PDF preview

private struct PDFPreview: View {
    let data: Data

    var body: some View {
        PDFKitView(data: data)
            .edgesIgnoringSafeArea(.bottom)
    }
}

/// Thin `UIViewRepresentable` over `PDFView`.
private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil || uiView.document?.pageCount == 0 {
            uiView.document = PDFDocument(data: data)
        }
    }
}

// MARK: - Markdown preview

private struct MarkdownPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

// MARK: - Code preview (Highlightr)

private struct CodePreview: View {
    let text: String
    let language: String?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            highlightedText
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black.opacity(0.92))
    }

    /// Builds an `AttributedString` via Highlightr and falls back to a
    /// monospaced `Text` when the highlighter refuses the language.
    private var highlightedText: Text {
        let highlighter = HighlightHolder.shared
        if let highlighted = highlighter?.highlight(text, as: language, fastRender: true) {
            return Text(AttributedString(highlighted))
        }
        return Text(text.isEmpty ? " " : text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
    }
}

// MARK: - Plain text preview (preserves prior behaviour)

private struct TextPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? " " : text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }
}

// MARK: - Binary preview placeholder

private struct BinaryPreview: View {
    let filename: String
    let mime: String
    let sizeBytes: Int64

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(filename)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(mime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Binary file — preview not available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
