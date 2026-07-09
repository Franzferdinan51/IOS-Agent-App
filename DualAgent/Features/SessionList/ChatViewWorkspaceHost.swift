import SwiftUI

/// Lightweight helper so ChatView doesn't have to inline the workspace
/// sheet content. Kept in its own file because SwiftUI's type-checker
/// has trouble resolving `WorkspaceBrowserView`-typed members when the
/// same file also contains a `private struct <Content: View>` generic.
struct ChatViewWorkspaceHost: View {
    let session: UnifiedSession?
    var body: some View {
        if let session {
            FileBrowserView(sessionId: session.id, sessionTitle: session.title)
        } else {
            Text("No session selected.")
                .padding()
        }
    }
}
