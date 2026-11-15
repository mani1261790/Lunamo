import AppKit
import MarimoApplication
import UniformTypeIdentifiers

@MainActor
public enum NotebookOpenActions {
  private static let jupyterNotebookType = UTType(
    importedAs: "org.jupyter.ipynb",
    conformingTo: .json
  )

  public static func open(_ store: NotebookStore) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.directoryURL = store.notebookDirectoryURL
    panel.message = localizedUI("Open a marimo notebook or import a Jupyter/Python file.")
    panel.prompt = localizedUI("Open")
    panel.allowedContentTypes = [
      UTType(filenameExtension: "py") ?? .plainText,
      jupyterNotebookType,
    ]
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      open(url, store: store)
    }
  }

  public static func open(_ url: URL, store: NotebookStore) {
    Task { @MainActor in
      if url.pathExtension.lowercased() == "ipynb" {
        await prepareImport(url, store: store)
        return
      }

      await store.open(url)
      if case .convertible(let convertibleURL) = store.openState {
        await prepareImport(convertibleURL, store: store)
      }
    }
  }

  private static func prepareImport(_ sourceURL: URL, store: NotebookStore) async {
    do {
      let draft = try await store.prepareImport(from: sourceURL)
      presentImportDestination(for: draft, store: store)
    } catch {
      // NotebookStore has already published a structured conversion error.
    }
  }

  private static func presentImportDestination(
    for draft: NotebookImportDraft,
    store: NotebookStore
  ) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.directoryURL = draft.sourceURL.deletingLastPathComponent()
    panel.nameFieldStringValue = draft.suggestedFilename
    panel.title = localizedUI("Import as marimo Notebook")
    panel.message = localizedUI(
      "The source stays unchanged. Save the converted notebook as a separate Python file."
    )
    panel.prompt = localizedUI("Save and Open")
    if let pythonType = UTType(filenameExtension: "py") {
      panel.allowedContentTypes = [pythonType]
    }
    panel.begin { response in
      guard response == .OK, let destinationURL = panel.url else { return }
      Task { @MainActor in
        do {
          try await store.saveImportedNotebook(draft, to: destinationURL)
        } catch NotebookImportError.sourceAndDestinationMatch {
          let alert = NSAlert()
          alert.alertStyle = .warning
          alert.messageText = localizedUI("Choose a Different File")
          alert.informativeText = localizedUI(
            "The imported notebook cannot replace its source file."
          )
          alert.addButton(withTitle: localizedUI("Choose Again"))
          alert.runModal()
          presentImportDestination(for: draft, store: store)
        } catch {
          store.reportImportSaveFailure(error, sourceURL: destinationURL)
        }
      }
    }
  }
}
