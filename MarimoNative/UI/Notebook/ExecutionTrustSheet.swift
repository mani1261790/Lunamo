import MarimoApplication
import SwiftUI

struct ExecutionTrustSheet: View {
  let store: NotebookStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Run Python Code?", systemImage: "exclamationmark.shield")
        .font(.title2.bold())
      Text(
        "This notebook can execute arbitrary Python code with your user permissions. Opening the file did not execute its code."
      )
      .fixedSize(horizontal: false, vertical: true)
      if let folder = trustFolder {
        LabeledContent("Folder", value: folder.path)
          .textSelection(.enabled)
      }
      HStack {
        Button("Cancel") { store.cancelExecutionTrust() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Trust This Folder") {
          Task { await store.trustCurrentFolder() }
        }
        Button("Run Once") { store.authorizeRunOnce() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 560)
    .interactiveDismissDisabled()
  }

  private var trustFolder: URL? {
    store.executionTrustFolderURL
  }
}
