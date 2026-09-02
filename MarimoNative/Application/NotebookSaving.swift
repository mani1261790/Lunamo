import Foundation
import MarimoDomain

extension NotebookStore {
  public func recordSuccessfulSave(fileIdentity: FileIdentity? = nil) async {
    if let fileIdentity { document.lastSavedFileIdentity = fileIdentity }
    guard synchronizedURI == document.notebookURI else { return }
    do {
      try await backend.didSaveNotebook(uri: document.notebookURI)
      document.dirty = false
      ignoreExternalChangesUntilNextSave = false
      synchronizationError = nil
      await recordRecentDocument(document.sourceURL)
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func save() async throws -> SaveOutcome {
    guard let target = document.sourceURL else { return .needsDestination }
    guard document.dirty else { return .unchanged }
    guard saveConflictURL == nil, !isPresentedFileDeleted else {
      throw AtomicWriteError.conflict(target)
    }
    guard let expected = document.lastSavedFileIdentity else {
      presentExternalConflict(at: target)
      throw AtomicWriteError.conflict(target)
    }
    return try await saveCurrentDocument(to: target, expecting: .matching(expected))
  }

  public func saveAs(to target: URL) async throws -> SaveOutcome {
    let target = target.standardizedFileURL
    if document.sourceURL?.standardizedFileURL == target {
      return try await save()
    }
    return try await saveCurrentDocument(to: target, expecting: .unchecked, moving: true)
  }

  public func close() async {
    guard !document.dirty else {
      saveMessage = "Save changes before closing this notebook."
      return
    }
    await closeDiscardingChanges()
  }

  public func closeDiscardingChanges() async {
    stopFileMonitoring()
    do {
      try await closeDocumentSynchronization()
      document.dirty = false
      resetSessionState(to: .closed)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  func saveCurrentDocument(
    to target: URL,
    expecting expectation: AtomicWriteExpectation,
    moving: Bool = false
  ) async throws -> SaveOutcome {
    let source = try await backend.printNotebook(document.persistentDocumentForSaving())
    let identity: FileIdentity
    do {
      identity = try await fileWriter.write(source: source, to: target, expecting: expectation)
    } catch let error as AtomicWriteError {
      if case .conflict = error { presentExternalConflict(at: document.sourceURL ?? target) }
      throw error
    }

    if moving {
      return try await adoptSaveAs(target: target, identity: identity)
    }
    document.lastSavedFileIdentity = identity
    try await backend.didSaveNotebook(uri: document.notebookURI)
    document.dirty = false
    saveConflictURL = nil
    externalFileState = .none
    conflictBannerDismissed = false
    ignoreExternalChangesUntilNextSave = false
    saveMessage = nil
    await recordRecentDocument(target)
    restartFileMonitoring(at: target)
    return .saved(target)
  }

  func adoptSaveAs(target: URL, identity: FileIdentity) async throws -> SaveOutcome {
    let oldURI = document.notebookURI
    let newURI = target.resolvingSymlinksInPath().standardizedFileURL.absoluteString
    let hadLiveSession = document.kernelSessionID != nil
    var sessionMoveFailed = false

    stopFileMonitoring()
    if hadLiveSession {
      do {
        try await backend.moveSession(notebookURI: oldURI, newNotebookURI: newURI)
      } catch {
        sessionMoveFailed = true
      }
    }
    document.sourceURL = target
    document.lastSavedFileIdentity = identity
    if synchronizedURI == oldURI {
      if sessionMoveFailed {
        try? await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
      } else {
        try await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
      }
      synchronizedURI = nil
      synchronizedCellURIs = []
    }

    if sessionMoveFailed {
      try? await backend.closeSession(notebookURI: oldURI)
      document.kernelSessionID = nil
      widgetValueStore.clear()
      variables = []
      for index in document.cells.indices {
        document.cells[index].runtime = CellRuntimeState()
      }
      saveMessage = "The file was saved, but the previous Python session could not be moved."
    } else {
      saveMessage = nil
    }
    try await synchronizeOpenDocument()
    try await backend.didSaveNotebook(uri: newURI)
    await refreshSidebarFiles()
    await recordRecentDocument(target)
    document.dirty = false
    saveConflictURL = nil
    externalFileState = .none
    conflictBannerDismissed = false
    ignoreExternalChangesUntilNextSave = false
    restartFileMonitoring(at: target)
    return sessionMoveFailed ? .savedWithSessionReset(target) : .saved(target)
  }

  func closeDocumentSynchronization() async throws {
    let uri = synchronizedURI ?? document.notebookURI
    try await closeSynchronizedDocument()
    if document.kernelSessionID != nil {
      try await backend.closeSession(notebookURI: uri)
      document.kernelSessionID = nil
      widgetValueStore.clear()
      variables = []
    }
  }
}
