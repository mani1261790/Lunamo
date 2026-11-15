import AppKit
import MarimoApplication
import UniformTypeIdentifiers

@MainActor
public enum NotebookSaveActions {
  public static func save(
    _ store: NotebookStore,
    completion: (@MainActor @Sendable (Bool) -> Void)? = nil
  ) {
    Task { @MainActor in
      do {
        switch try await store.save() {
        case .needsDestination:
          presentSavePanel(store, completion: completion)
        case .unchanged, .saved, .savedWithSessionReset:
          completion?(true)
        }
      } catch {
        if !(error is AtomicWriteError) || store.saveConflictURL == nil {
          store.reportSaveFailure(error)
        }
        completion?(false)
      }
    }
  }

  public static func saveAs(
    _ store: NotebookStore,
    completion: (@MainActor @Sendable (Bool) -> Void)? = nil
  ) {
    presentSavePanel(store, completion: completion)
  }

  private static func presentSavePanel(
    _ store: NotebookStore,
    completion: (@MainActor @Sendable (Bool) -> Void)?
  ) {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = store.document.sourceURL?.lastPathComponent ?? "Untitled.py"
    panel.directoryURL =
      store.document.sourceURL?.deletingLastPathComponent()
      ?? store.applicationWorkspaceDirectory
    if let pythonType = UTType(filenameExtension: "py") {
      panel.allowedContentTypes = [pythonType]
    }
    panel.begin { response in
      guard response == .OK, let target = panel.url else {
        completion?(false)
        return
      }
      Task { @MainActor in
        do {
          _ = try await store.saveAs(to: target)
          completion?(true)
        } catch {
          if !(error is AtomicWriteError) || store.saveConflictURL == nil {
            store.reportSaveFailure(error)
          }
          completion?(false)
        }
      }
    }
  }
}
