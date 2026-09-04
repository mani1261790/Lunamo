import Foundation
import MarimoEnvironment

extension NotebookStore {
  public func refreshInstalledPackages() async {
    guard case .ready(let details, _) = environmentState else {
      installedPackages = []
      packagesError = "Choose and validate a Python environment first."
      return
    }
    packagesLoading = true
    packagesError = nil
    defer { packagesLoading = false }
    do {
      installedPackages = try await backend.listPackages(
        notebookURI: document.notebookURI,
        executable: details.executableURL.path
      )
    } catch {
      installedPackages = []
      packagesError = "Packages could not be read: \(error.localizedDescription)"
    }
  }

  public func discoverPythonEnvironments(for notebookURL: URL) async {
    runOnceAuthorized = false
    executionFolderTrusted = false
    executionTrustPromptPresented = false
    environmentCandidates = await environmentDiscovery.candidates(for: notebookURL)
    guard let first = environmentCandidates.first else {
      environmentState = .notConfigured
      return
    }
    environmentState = .selected(
      first,
      workingDirectory: canonicalURL(notebookURL).deletingLastPathComponent()
    )
  }

  public func choosePythonExecutable(_ executableURL: URL) async {
    let candidate = PythonEnvironmentCandidate(
      executableURL: normalizedExecutableURL(executableURL),
      kind: .userSelected
    )
    environmentCandidates.removeAll {
      normalizedExecutableURL($0.executableURL) == candidate.executableURL
    }
    environmentCandidates.append(candidate)
    await selectPythonEnvironment(candidate)
  }

  public func selectPythonEnvironment(_ candidate: PythonEnvironmentCandidate) async {
    environmentState = .checking(candidate)
    do {
      let details = try await environmentPreflight.inspect(candidate)
      if let sourceURL = document.sourceURL {
        let workspaceRoot = WorkspaceResolver.workspaceRoot(for: sourceURL)
        try await environmentDiscovery.remember(details, for: workspaceRoot)
        environmentState = .ready(
          details,
          workingDirectory: canonicalURL(sourceURL).deletingLastPathComponent()
        )
        executionFolderTrusted = await folderTrustStore.isTrusted(
          folder: WorkspaceResolver.workspaceRoot(for: sourceURL),
          notebookURL: sourceURL
        )
      } else {
        environmentState = .needsWorkingDirectory(details)
        executionFolderTrusted = false
      }
      runOnceAuthorized = false
    } catch let failure as PythonPreflightFailure {
      environmentState = .invalid(candidate, failure)
    } catch {
      environmentState = .invalid(candidate, .launchFailed(error.localizedDescription))
    }
  }

  public func chooseWorkingDirectory(_ directory: URL) {
    let canonical = canonicalURL(directory)
    var isDirectory: ObjCBool = false
    guard directory.isFileURL, directory.path.hasPrefix("/"),
      FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      saveMessage = "Working directory must be an existing absolute directory."
      return
    }
    switch environmentState {
    case .ready(let details, _), .needsWorkingDirectory(let details):
      environmentState = .ready(details, workingDirectory: canonical)
      saveMessage = nil
      runOnceAuthorized = false
    case .selected(let candidate, _):
      environmentState = .selected(candidate, workingDirectory: canonical)
      saveMessage = nil
    case .notConfigured, .checking, .invalid:
      saveMessage = "Choose a valid Python environment first."
    }
  }

  public func requestExecutionAuthorization() async -> Bool {
    if runOnceAuthorized { return true }
    if case .selected(let candidate, _) = environmentState {
      await selectPythonEnvironment(candidate)
      guard case .ready = environmentState else { return false }
      return await requestExecutionAuthorization()
    }
    guard case .ready(let details, let workingDirectory) = environmentState else {
      saveMessage = "A valid Python 3.10–3.14 environment with marimo 0.24.0 is required."
      return false
    }
    guard (try? executableIdentity(at: details.executableURL)) == details.identity else {
      environmentState = .invalid(
        PythonEnvironmentCandidate(executableURL: details.executableURL, kind: details.kind),
        .executableChanged(details.executableURL)
      )
      return false
    }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      environmentState = .needsWorkingDirectory(details)
      return false
    }
    let folder = executionTrustFolder(workingDirectory: workingDirectory)
    executionFolderTrusted = await folderTrustStore.isTrusted(
      folder: folder, notebookURL: document.sourceURL
    )
    if executionFolderTrusted { return true }
    executionTrustPromptPresented = true
    return false
  }

  public func authorizeRunOnce() {
    runOnceAuthorized = true
    executionTrustPromptPresented = false
    resumePendingRun()
  }

  public func trustCurrentFolder() async {
    guard case .ready(_, let workingDirectory) = environmentState else { return }
    let folder = executionTrustFolder(workingDirectory: workingDirectory)
    do {
      try await folderTrustStore.trust(folder: folder, notebookURL: document.sourceURL)
      guard await folderTrustStore.isTrusted(folder: folder, notebookURL: document.sourceURL) else {
        saveMessage = "This folder cannot be trusted while it is remote or quarantined."
        return
      }
      executionFolderTrusted = true
      executionTrustPromptPresented = false
      await executePendingRun()
    } catch {
      saveMessage = "Folder trust could not be saved: \(error.localizedDescription)"
    }
  }

  public func cancelExecutionTrust() {
    runOnceAuthorized = false
    executionFolderTrusted = false
    executionTrustPromptPresented = false
    pendingRunRequest = nil
  }

  public func consumeExecutionAuthorization() async -> Bool {
    if runOnceAuthorized {
      runOnceAuthorized = false
      return true
    }
    guard case .ready(_, let workingDirectory) = environmentState else { return false }
    executionFolderTrusted = await folderTrustStore.isTrusted(
      folder: executionTrustFolder(workingDirectory: workingDirectory),
      notebookURL: document.sourceURL
    )
    return executionFolderTrusted
  }

  public var environmentAllowsExecutionRequest: Bool {
    switch environmentState {
    case .selected, .ready: true
    case .notConfigured, .checking, .invalid, .needsWorkingDirectory: false
    }
  }

  public var interactiveWidgetsAllowed: Bool {
    runOnceAuthorized || executionFolderTrusted
  }

  public var executionAuthorizationLabel: String {
    if executionFolderTrusted { return "Trusted" }
    if runOnceAuthorized { return "Run Once" }
    return "Ask on Run"
  }

  public var executionTrustFolderURL: URL? {
    switch environmentState {
    case .ready(_, let workingDirectory): executionTrustFolder(workingDirectory: workingDirectory)
    case .selected(_, let workingDirectory):
      workingDirectory.map { executionTrustFolder(workingDirectory: $0) }
    case .notConfigured, .checking, .invalid, .needsWorkingDirectory: nil
    }
  }

  private func executionTrustFolder(workingDirectory: URL) -> URL {
    if let sourceURL = document.sourceURL {
      return WorkspaceResolver.workspaceRoot(for: sourceURL)
    }
    return canonicalURL(workingDirectory)
  }
}
