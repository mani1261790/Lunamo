import Foundation
import MarimoEnvironment

extension NotebookStore {
  public func setPackageEnvironmentScope(_ scope: ManagedPythonEnvironmentScope) async {
    guard scope != packageEnvironmentScope else { return }
    let workspace = managedEnvironmentWorkspaceURL()
    do {
      try await managedEnvironmentStore.setScope(scope, for: workspace)
      packageEnvironmentScope = scope
      environmentStorageMessage = nil
      if document.kernelSessionID != nil {
        try? await backend.closeSession(notebookURI: document.notebookURI)
        resetSessionState(to: .notStarted)
      }
      environmentState = .notConfigured
      await refreshPythonEnvironments()
    } catch {
      environmentStorageMessage = error.localizedDescription
    }
  }

  public func refreshManagedEnvironmentStorage() async {
    let workspace = managedEnvironmentWorkspaceURL()
    managedEnvironmentSummaries = await managedEnvironmentStore.summaries(
      for: workspace, currentScope: packageEnvironmentScope)
    managedPackageCacheSize = await managedEnvironmentStore.uvCacheSize()
  }

  public func removeManagedEnvironment(_ scope: ManagedPythonEnvironmentScope) async {
    guard !packageOperationState.isRunning else { return }
    let workspace = managedEnvironmentWorkspaceURL()
    do {
      if scope == packageEnvironmentScope, document.kernelSessionID != nil {
        try? await backend.closeSession(notebookURI: document.notebookURI)
        resetSessionState(to: .notStarted)
      }
      _ = try await managedEnvironmentStore.moveEnvironmentToTrash(
        scope: scope, workspaceURL: workspace)
      environmentStorageMessage = "The environment was moved to Trash."
      if scope == packageEnvironmentScope {
        environmentState = .notConfigured
        await refreshPythonEnvironments()
      } else {
        await refreshManagedEnvironmentStorage()
      }
    } catch {
      environmentStorageMessage = error.localizedDescription
    }
  }

  public func rebuildManagedEnvironment(_ scope: ManagedPythonEnvironmentScope) async {
    guard !packageOperationState.isRunning, let packageManager else { return }
    let workspace = managedEnvironmentWorkspaceURL()
    guard let base = rebuildBaseCandidate else {
      environmentStorageMessage =
        "No compatible base Python is available to rebuild the environment."
      return
    }
    do {
      packageOperationState = .preparingEnvironment
      if scope == packageEnvironmentScope, document.kernelSessionID != nil {
        try? await backend.closeSession(notebookURI: document.notebookURI)
        resetSessionState(to: .notStarted)
      }
      _ = try await managedEnvironmentStore.moveEnvironmentToTrash(
        scope: scope, workspaceURL: workspace)
      let environmentURL = await managedEnvironmentStore.environmentURL(
        for: scope, workspaceURL: workspace)
      let pythonURL = try await packageManager.createEnvironment(
        at: environmentURL,
        basePythonURL: base.executableURL,
        workingDirectoryURL: notebookWorkingDirectory
          ?? document.sourceURL?.deletingLastPathComponent()
          ?? applicationWorkspaceDirectory
      )
      let candidate = PythonEnvironmentCandidate(
        executableURL: pythonURL,
        kind: scope == .shared
          ? .applicationSharedEnvironment : .projectManagedEnvironment)
      packageOperationState = .idle
      environmentStorageMessage =
        "The environment was rebuilt. Packages can now be installed again."
      if scope == packageEnvironmentScope {
        await selectPythonEnvironment(candidate)
      }
      await refreshManagedEnvironmentStorage()
    } catch {
      packageOperationState = .failed(error.localizedDescription)
      environmentStorageMessage = error.localizedDescription
    }
  }

  public func cleanUnusedManagedEnvironments() async {
    do {
      let removed = try await managedEnvironmentStore.moveUnusedProjectEnvironmentsToTrash(
        olderThan: Date().addingTimeInterval(-30 * 24 * 60 * 60),
        excluding: managedEnvironmentWorkspaceURL()
      )
      environmentStorageMessage =
        removed == 0
        ? "No unused project environments were found."
        : "Unused project environments were moved to Trash."
      await refreshManagedEnvironmentStorage()
    } catch {
      environmentStorageMessage = error.localizedDescription
    }
  }

  public func clearManagedPackageCache() async {
    do {
      try await managedEnvironmentStore.clearUVCache()
      environmentStorageMessage = "The Lunamo package cache was moved to Trash."
      await refreshManagedEnvironmentStorage()
    } catch {
      environmentStorageMessage = error.localizedDescription
    }
  }

  func managedEnvironmentCandidate(
    scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL
  ) async -> PythonEnvironmentCandidate? {
    let pythonURL = await managedEnvironmentStore.pythonURL(for: scope, workspaceURL: workspaceURL)
    guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else { return nil }
    return PythonEnvironmentCandidate(
      executableURL: pythonURL,
      kind: scope == .shared ? .applicationSharedEnvironment : .projectManagedEnvironment,
      expectedIdentity: try? executableIdentity(at: pythonURL)
    )
  }

  func managedEnvironmentWorkspaceURL(for notebookURL: URL? = nil) -> URL {
    if let notebookURL = notebookURL ?? document.sourceURL {
      return WorkspaceResolver.workspaceRoot(for: notebookURL)
    }
    return applicationWorkspaceDirectory
  }

  func prioritizeBundledEnvironmentCandidate() {
    guard let index = environmentCandidates.firstIndex(where: { $0.kind == .bundled }), index != 0
    else { return }
    environmentCandidates.insert(environmentCandidates.remove(at: index), at: 0)
  }

  private var rebuildBaseCandidate: PythonEnvironmentCandidate? {
    environmentCandidates.first { candidate in
      guard candidate.kind != .applicationSharedEnvironment,
        candidate.kind != .projectManagedEnvironment,
        case .ready = environmentAvailability[candidate.id]
      else { return false }
      return true
    }
  }
}
