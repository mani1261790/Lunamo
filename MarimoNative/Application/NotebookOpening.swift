import Foundation
import MarimoDomain

extension NotebookStore {
  public func open(_ url: URL) async {
    MarimoLog.document.info(
      "Opening notebook at \(MarimoLogPrivacy.redactHomePrefix(in: url.path), privacy: .public)"
    )
    openState = .loading(url)
    do {
      let snapshot = try await documentService.readSnapshot(at: url)
      if backendStatus != .ready {
        try await backend.start()
        backendStatus = await backend.status()
      }
      switch try await backend.parseNotebook(source: snapshot.source) {
      case .success(let parsed):
        for revision in markdownRevisions.values {
          pendingTextSynchronizations.removeValue(forKey: revision)
        }
        markdownRevisions.removeAll()
        stopFileMonitoring()
        try await closeDocumentSynchronization()
        resetSessionState(to: .notStarted)
        document = NotebookDocumentState(
          sourceURL: url,
          owned: parsed.owned,
          dirty: false,
          lastSavedFileIdentity: snapshot.identity
        )
        await restoreTextCellProjections()
        focusedCellID = nil
        saveConflictURL = nil
        externalFileState = .none
        conflictBannerDismissed = false
        ignoreExternalChangesUntilNextSave = false
        userFacingError = nil
        saveMessage = nil
        missingPackages = []
        packageOperationState = .idle
        try await synchronizeOpenDocument()
        openState = .loaded(url)
        await refreshSidebarFiles()
        await discoverPythonEnvironments(for: url)
        await reattachSessionIfAvailable()
        await recordRecentDocument(url)
        restartFileMonitoring(at: url)
      case .invalidSyntax(let line, let column):
        openState = .invalidSyntax(url, line: line, column: column)
        presentError(
          code: .documentSyntax,
          cause:
            "Python syntax error at line \(line.map(String.init) ?? "unknown"), column \(column.map(String.init) ?? "unknown").",
          target: url.path,
          recoveryActions: ["Edit the source in another application", "Open Another Notebook"]
        )
      case .convertible:
        openState = .convertible(url)
        presentError(
          code: .documentConvert,
          cause: "The source is Python, but it is not a marimo notebook.",
          target: url.path,
          recoveryActions: ["Open Another Notebook"]
        )
      }
    } catch {
      openState = .failed(url, String(describing: error))
      presentError(
        code: errorCode(for: error),
        cause: error.localizedDescription,
        target: url.path,
        recoveryActions: ["Retry", "Open Another Notebook"]
      )
    }
  }

}
