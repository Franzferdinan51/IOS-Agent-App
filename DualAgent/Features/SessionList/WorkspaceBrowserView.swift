//
//  FileBrowserView.swift
//  DualAgent
//
//  Read-only browser for a session's workspace files. Backed by the
//  unified `Backend.listWorkspace` / `readFile` / `readFileRaw` surface
//  which both Hermes (`/api/list`, `/api/file`) and OpenClaw
//  (`sessions.files.list`, `sessions.files.get`) implement.
//

import SwiftUI

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
                                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
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
}

struct FilePreviewSheet: View {
    let sessionId: String
    let file: WorkspaceEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand

    @State private var content: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading \(file.name)…")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.error)
                        .padding()
                } else {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !content.isEmpty {
                            UIPasteboard.general.string = content
                            Haptic.tap()
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                content = try await AuthManager.shared.backend.readFile(
                    sessionId: sessionId,
                    path: file.path
                ).content
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
