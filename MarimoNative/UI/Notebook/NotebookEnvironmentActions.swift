import AppKit
import MarimoApplication

@MainActor
enum NotebookEnvironmentActions {
  static func chooseExecutable(for store: NotebookStore) {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Choose Python Executable")
    panel.message =
      String(localized: "Select a Python executable. Lunamo will inspect it without installing packages.")
    panel.prompt = String(localized: "Choose Python")
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
    panel.title = String(localized: "Choose Working Directory")
    panel.message = String(localized: "Choose the directory used when Python execution starts.")
    panel.prompt = String(localized: "Choose Directory")
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      store.chooseWorkingDirectory(url)
    }
  }
}
