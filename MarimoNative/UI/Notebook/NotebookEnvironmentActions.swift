import AppKit
import MarimoApplication

@MainActor
enum NotebookEnvironmentActions {
  static func chooseExecutable(for store: NotebookStore) {
    let panel = NSOpenPanel()
    panel.title = "Choose Python Executable"
    panel.message =
      "Select a Python executable. MarimoNative will inspect it without installing packages."
    panel.prompt = "Choose Python"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in await store.choosePythonExecutable(url) }
    }
  }

  static func chooseWorkingDirectory(for store: NotebookStore) {
    let panel = NSOpenPanel()
    panel.title = "Choose Working Directory"
    panel.message = "Choose the directory used when Python execution starts."
    panel.prompt = "Choose Directory"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      store.chooseWorkingDirectory(url)
    }
  }
}
