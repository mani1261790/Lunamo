import MarimoApplication
import SwiftUI

struct NotebookTerminalView: View {
  @ObservedObject var session: NotebookTerminalSession
  let directoryURL: URL?
  let pythonEnvironment: [String: String]
  let saveNotebook: () -> Void
  let close: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .background(.regularMaterial)
    .task(id: terminalIdentity) {
      guard let directoryURL else { return }
      await session.start(in: directoryURL, pythonEnvironment: pythonEnvironment)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localizedUI("Terminal"))
  }

  private var terminalIdentity: String {
    "\(directoryURL?.path ?? "")|\(pythonEnvironment["VIRTUAL_ENV"] ?? "")"
  }

  private var header: some View {
    HStack(spacing: 10) {
      Label(localizedUI("Terminal"), systemImage: "terminal")
        .font(.headline)
      if let directoryURL {
        Text(directoryURL.lastPathComponent)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button(localizedUI("Clear Terminal"), systemImage: "trash", action: session.clear)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(localizedUI("Clear Terminal"))
      Button(localizedUI("Close Terminal"), systemImage: "xmark", action: close)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(localizedUI("Close Terminal"))
    }
    .padding(.horizontal, 14)
    .frame(height: 42)
  }

  @ViewBuilder
  private var content: some View {
    if directoryURL == nil {
      ContentUnavailableView {
        Label(localizedUI("Save the notebook to use Terminal"), systemImage: "folder.badge.plus")
      } description: {
        Text(localizedUI("The Terminal starts in the notebook's saved folder."))
      } actions: {
        Button(localizedUI("Name and Save…"), action: saveNotebook)
          .buttonStyle(.borderedProminent)
      }
    } else {
      TerminalConsoleView(session: session)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.62))
    }
  }
}
