import Foundation
import MarimoDomain

extension NotebookStore {
  public var isPresentedFileDeleted: Bool {
    if case .deleted = externalFileState { return true }
    return false
  }

  public var recoverySource: String? {
    if case .recovery(_, let source, _, _) = externalFileState { return source }
    return nil
  }

  public func loadRecentDocuments() async {
    recentDocuments = await recentDocumentStore.load()
  }

  func recordRecentDocument(_ url: URL?) async {
    guard let url else { return }
    do {
      recentDocuments = try await recentDocumentStore.record(url)
    } catch {
      presentError(
        code: .documentSave,
        cause: "Recent document metadata could not be saved: \(error.localizedDescription)",
        target: RecentDocumentStore.defaultFileURL.path,
        recoveryActions: ["Continue without Recent Documents"]
      )
    }
  }

  public func startFileMonitoring() {
    guard let url = document.sourceURL else { return }
    restartFileMonitoring(at: url)
  }

  func restartFileMonitoring(at url: URL) {
    stopFileMonitoring()
    filePresenter = NotebookFilePresenter(url: url) { [weak self] event in
      Task { @MainActor [weak self] in await self?.handlePresentedFileEvent(event) }
    }
  }

  func stopFileMonitoring() {
    filePresenter?.stop()
    filePresenter = nil
  }

  func handlePresentedFileEvent(_ event: NotebookPresentedFileEvent) async {
    switch event {
    case .changed(let url):
      await handlePresentedFileChange(at: url)
    case .moved(let oldURL, let newURL):
      await handlePresentedFileMove(from: oldURL, to: newURL)
    case .deleted(let url):
      if FileManager.default.fileExists(atPath: url.path) {
        await handlePresentedFileChange(at: url)
      } else {
        await handlePresentedFileDeletion(at: url)
      }
    }
  }

  private func handlePresentedFileChange(at url: URL) async {
    guard document.sourceURL?.standardizedFileURL == url.standardizedFileURL else { return }
    guard let identity = try? await fileWriter.identity(at: url) else {
      await handlePresentedFileDeletion(at: url)
      return
    }
    if identity == document.lastSavedFileIdentity {
      restartFileMonitoring(at: url)
      return
    }
    guard !ignoreExternalChangesUntilNextSave else { return }
    presentExternalConflict(at: url)
  }

  func presentExternalConflict(at url: URL) {
    externalFileState = .changed(url, localDirty: document.dirty)
    saveConflictURL = document.dirty ? url : nil
    conflictBannerDismissed = false
    userFacingError = NotebookUserFacingError(
      code: .documentConflict,
      cause: "The file contents changed outside Lunamo.",
      target: url.path,
      recoveryActions: document.dirty
        ? ["Reload from Disk", "Save Local Copy", "Cancel"]
        : ["Reload from Disk", "Ignore Until Next Save"]
    )
  }

  public func ignoreExternalChanges() async {
    guard case .changed(let url, localDirty: false) = externalFileState else { return }
    if let identity = try? await fileWriter.identity(at: url) {
      document.lastSavedFileIdentity = identity
    }
    ignoreExternalChangesUntilNextSave = true
    externalFileState = .none
    userFacingError = nil
  }

  public func dismissConflictBanner() {
    guard saveConflictURL != nil else { return }
    conflictBannerDismissed = true
  }

  public func reloadPresentedFile() async {
    let target: URL
    switch externalFileState {
    case .changed(let url, _), .recovery(let url, _, _, _): target = url
    case .deleted, .none: return
    }

    let diskSnapshot: DocumentSourceSnapshot
    do {
      diskSnapshot = try await documentService.readSnapshot(at: target)
    } catch {
      presentReloadRecovery(
        url: target,
        source: (try? String(contentsOf: target, encoding: .utf8)) ?? "",
        code: errorCode(for: error),
        cause: error.localizedDescription
      )
      return
    }

    stopFileMonitoring()
    do {
      try await closeDocumentSynchronization()
    } catch {
      presentReloadRecovery(
        url: target,
        source: diskSnapshot.source,
        code: .lspProtocol,
        cause: "The previous live session could not be closed: \(error.localizedDescription)"
      )
      restartFileMonitoring(at: target)
      return
    }
    resetSessionState(to: .notStarted)
    for index in document.cells.indices { document.cells[index].runtime = CellRuntimeState() }
    variables = []

    do {
      switch try await backend.parseNotebook(source: diskSnapshot.source) {
      case .success(let parsed):
        document = NotebookDocumentState(
          sourceURL: target,
          owned: parsed.owned,
          dirty: false,
          lastSavedFileIdentity: diskSnapshot.identity
        )
        await restoreTextCellProjections()
        focusedCellID = nil
        saveConflictURL = nil
        externalFileState = .none
        conflictBannerDismissed = false
        ignoreExternalChangesUntilNextSave = false
        userFacingError = nil
        try await synchronizeOpenDocument()
        openState = .loaded(target)
        await refreshSidebarFiles()
        await discoverPythonEnvironments(for: target)
        await recordRecentDocument(target)
        restartFileMonitoring(at: target)
      case .invalidSyntax(let line, let column):
        let location =
          "line \(line.map(String.init) ?? "unknown"), column \(column.map(String.init) ?? "unknown")"
        presentReloadRecovery(
          url: target, source: diskSnapshot.source, code: .documentSyntax,
          cause: "The external source has invalid Python syntax at \(location).")
        restartFileMonitoring(at: target)
      case .convertible:
        presentReloadRecovery(
          url: target, source: diskSnapshot.source, code: .documentConvert,
          cause: "The external source is Python, but it is not a marimo notebook.")
        restartFileMonitoring(at: target)
      }
    } catch {
      presentReloadRecovery(
        url: target, source: diskSnapshot.source, code: .lspProtocol,
        cause: error.localizedDescription)
      restartFileMonitoring(at: target)
    }
  }

  private func presentReloadRecovery(
    url: URL,
    source: String,
    code: NotebookUserFacingError.Code,
    cause: String
  ) {
    externalFileState = .recovery(url: url, source: source, code: code.rawValue, cause: cause)
    userFacingError = NotebookUserFacingError(
      code: code,
      cause: cause,
      target: url.path,
      recoveryActions: ["View Disk Source", "Save Local Copy", "Cancel"]
    )
  }

  private func handlePresentedFileMove(from oldURL: URL, to newURL: URL) async {
    guard document.sourceURL?.standardizedFileURL == oldURL.standardizedFileURL else { return }
    guard newURL.pathExtension.lowercased() == "py",
      FileManager.default.fileExists(atPath: newURL.path)
    else {
      if FileManager.default.fileExists(atPath: oldURL.path) { restartFileMonitoring(at: oldURL) }
      return
    }
    stopFileMonitoring()
    let oldURI = document.notebookURI
    let newURI = newURL.resolvingSymlinksInPath().standardizedFileURL.absoluteString
    let hadLiveSession = document.kernelSessionID != nil
    var sessionMoveFailed = false

    if hadLiveSession {
      do {
        try await backend.moveSession(notebookURI: oldURI, newNotebookURI: newURI)
      } catch {
        sessionMoveFailed = true
      }
    }

    do {
      if synchronizedURI == oldURI {
        if sessionMoveFailed {
          try? await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
        } else {
          try await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
        }
        synchronizedURI = nil
        synchronizedCellURIs = []
      }
      document.sourceURL = newURL
      document.lastSavedFileIdentity = try await fileWriter.identity(at: newURL)
      openState = .loaded(newURL)
      if sessionMoveFailed {
        try? await backend.closeSession(notebookURI: oldURI)
        document.kernelSessionID = nil
        resetSessionState(to: .notStarted)
        for index in document.cells.indices { document.cells[index].runtime = CellRuntimeState() }
        variables = []
      }
      try await synchronizeOpenDocument()
      await refreshSidebarFiles()
      await recordRecentDocument(newURL)
      restartFileMonitoring(at: newURL)
      if sessionMoveFailed {
        presentError(
          code: .kernelCrash,
          cause: "The file moved, but the previous Python session could not follow it.",
          target: newURL.path,
          recoveryActions: ["Restart Kernel", "Continue Editing"]
        )
      }
    } catch {
      document.sourceURL = newURL
      openState = .loaded(newURL)
      restartFileMonitoring(at: newURL)
      presentError(
        code: .lspProtocol,
        cause:
          "The moved file could not be attached to the live session: \(error.localizedDescription)",
        target: newURL.path,
        recoveryActions: ["Save Local Copy", "Restart Kernel"]
      )
    }
  }

  private func handlePresentedFileDeletion(at url: URL) async {
    guard document.sourceURL?.standardizedFileURL == url.standardizedFileURL else { return }
    stopFileMonitoring()
    externalFileState = .deleted(url)
    saveConflictURL = url
    conflictBannerDismissed = false
    recentDocuments = (try? await recentDocumentStore.remove(url)) ?? recentDocuments
    presentError(
      code: .documentConflict,
      cause: "The notebook file was deleted outside Lunamo. The editor buffer is intact.",
      target: url.path,
      recoveryActions: ["Save As", "Close", "Recreate at Original Location"]
    )
  }

  public func recreatePresentedFile() async {
    guard case .deleted(let target) = externalFileState else { return }
    do {
      try await flushCommittedTextChanges()
      let source = try await backend.printNotebook(document.persistentDocumentForSaving())
      let identity = try await fileWriter.write(source: source, to: target, expecting: .missing)
      document.lastSavedFileIdentity = identity
      try await backend.didSaveNotebook(uri: document.notebookURI)
      document.dirty = false
      saveConflictURL = nil
      externalFileState = .none
      conflictBannerDismissed = false
      userFacingError = nil
      await recordRecentDocument(target)
      await refreshSidebarFiles()
      restartFileMonitoring(at: target)
    } catch {
      presentError(
        code: .documentSave,
        cause: error.localizedDescription,
        target: target.path,
        recoveryActions: ["Save As", "Retry"]
      )
    }
  }

  public func dismissUserFacingError() {
    userFacingError = nil
  }

  func presentError(
    code: NotebookUserFacingError.Code,
    cause: String,
    target: String,
    recoveryActions: [String]
  ) {
    userFacingError = NotebookUserFacingError(
      code: code, cause: cause, target: target, recoveryActions: recoveryActions)
  }

  func errorCode(for error: any Error) -> NotebookUserFacingError.Code {
    guard let documentError = error as? DocumentOpenError else { return .lspProtocol }
    switch documentError {
    case .invalidUTF8: return .documentUTF8
    case .fileTooLarge, .readFailed: return .documentConflict
    }
  }
}
