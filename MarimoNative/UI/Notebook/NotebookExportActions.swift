import AppKit
import MarimoApplication
import MarimoDomain
import UniformTypeIdentifiers

@MainActor
enum NotebookExportActions {
  static func present(_ format: NotebookExportFormat, store: NotebookStore) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    let stem = store.document.sourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    if let type = UTType(filenameExtension: format.filenameExtension) {
      panel.allowedContentTypes = [type]
    }
    panel.nameFieldStringValue = "\(stem).\(format.filenameExtension)"
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      Task { @MainActor in
        do {
          try await store.exportNotebook(format: format, to: destination)
        } catch {
          store.reportExportFailure(error, destination: destination)
        }
      }
    }
  }
}

@MainActor
enum NotebookLogExportActions {
  static func saveReviewedLog(_ store: NotebookStore, text: String) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    if let type = UTType(filenameExtension: "log") { panel.allowedContentTypes = [type] }
    panel.nameFieldStringValue = "Lunamo-diagnostic.log"
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      do {
        try store.saveReviewedDiagnostics(text, to: destination)
      } catch {
        store.reportExportFailure(error, destination: destination)
      }
    }
  }
}
