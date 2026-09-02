import AppKit
import MarimoApplication
import UniformTypeIdentifiers

@MainActor
public enum NotebookOpenActions {
  public static func open(_ store: NotebookStore) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.directoryURL = store.notebookDirectoryURL
    if let pythonType = UTType(filenameExtension: "py") {
      panel.allowedContentTypes = [pythonType]
    }
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in await store.open(url) }
    }
  }
}
