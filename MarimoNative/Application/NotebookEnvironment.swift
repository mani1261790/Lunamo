import Foundation
import MarimoEnvironment

extension NotebookStore {
  public var selectedPythonEnvironment: PythonEnvironmentDetails? {
    switch environmentState {
    case .ready(let details, _), .needsWorkingDirectory(let details): details
    case .notConfigured, .selected, .checking, .invalid: nil
    }
  }

  public var notebookWorkingDirectory: URL? {
    switch environmentState {
    case .ready(_, let directory): directory
    case .selected(_, let directory): directory
    case .notConfigured, .checking, .invalid, .needsWorkingDirectory: nil
    }
  }

  public var terminalPythonEnvironment: [String: String] {
    guard let details = selectedPythonEnvironment else { return [:] }
    let environmentRoot =
      details.executableURL.deletingLastPathComponent().deletingLastPathComponent()
    guard
      FileManager.default.fileExists(
        atPath: environmentRoot.appending(path: "pyvenv.cfg").path)
    else { return [:] }
    let bin = details.executableURL.deletingLastPathComponent().path
    let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    return [
      "PATH": "\(bin):\(inheritedPath)",
      "VIRTUAL_ENV": environmentRoot.path,
    ]
  }

  public func refreshPythonEnvironments() async {
    guard !environmentsSearching else { return }
    environmentsSearching = true
    defer { environmentsSearching = false }
    let location =
      document.sourceURL
      ?? applicationWorkspaceDirectory.appending(path: "Untitled.py")
    let workspace = managedEnvironmentWorkspaceURL(for: location)
    packageEnvironmentScope = await managedEnvironmentStore.scope(for: workspace)
    environmentCandidates = await environmentDiscovery.candidates(for: location)
    if let managed = await managedEnvironmentCandidate(
      scope: packageEnvironmentScope, workspaceURL: workspace)
    {
      environmentCandidates.removeAll { $0.executableURL == managed.executableURL }
      environmentCandidates.insert(managed, at: 0)
    } else {
      prioritizeBundledEnvironmentCandidate()
    }
    if case .notConfigured = environmentState, let first = environmentCandidates.first {
      environmentState = .selected(
        first,
        workingDirectory: document.sourceURL?.deletingLastPathComponent()
          ?? applicationWorkspaceDirectory)
    }
    environmentAvailability = Dictionary(
      uniqueKeysWithValues: environmentCandidates.map { ($0.id, .checking) }
    )
    await withTaskGroup(of: (PythonEnvironmentCandidate, PythonEnvironmentAvailability).self) {
      group in
      for candidate in environmentCandidates {
        group.addTask { [environmentPreflight] in
          do {
            return (candidate, .ready(try await environmentPreflight.inspect(candidate)))
          } catch let failure as PythonPreflightFailure {
            return (candidate, .unavailable(failure))
          } catch {
            return (candidate, .unavailable(.launchFailed(error.localizedDescription)))
          }
        }
      }
      for await (candidate, availability) in group {
        environmentAvailability[candidate.id] = availability
        guard case .selected(let selected, _) = environmentState, selected.id == candidate.id else {
          continue
        }
        switch availability {
        case .ready(let details):
          await activatePythonEnvironment(details)
        case .unavailable(let failure):
          environmentState = .invalid(candidate, failure)
        case .checking:
          break
        }
      }
    }
    await refreshManagedEnvironmentStorage()
  }

  public func refreshInstalledPackages() async {
    let details: PythonEnvironmentDetails
    switch environmentState {
    case .ready(let inspected, _), .needsWorkingDirectory(let inspected):
      details = inspected
    case .notConfigured, .selected, .checking, .invalid:
      installedPackages = []
      packagesLoaded = false
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
      packagesLoaded = true
    } catch {
      installedPackages = []
      packagesLoaded = false
      packagesError = "Packages could not be read: \(error.localizedDescription)"
    }
  }

  public func installPackages(_ requirements: [String]) async {
    guard !packageOperationState.isRunning else { return }
    guard let packageManager else {
      packageOperationState = .failed(NotebookPackageManagerError.unavailable.localizedDescription)
      return
    }
    guard case .ready(let initialDetails, let workingDirectory) = environmentState else {
      packageOperationState = .failed("A ready notebook environment is required.")
      return
    }

    do {
      let normalized = try requirements.map(UVNotebookPackageManager.validateRequirement)
      guard !normalized.isEmpty else { return }
      var targetDetails = initialDetails
      let workspace = managedEnvironmentWorkspaceURL()
      let environmentURL = await managedEnvironmentStore.environmentURL(
        for: packageEnvironmentScope, workspaceURL: workspace)
      let managedPythonURL = environmentURL.appending(path: "bin/python")
      if normalizedExecutableURL(initialDetails.executableURL)
        != normalizedExecutableURL(managedPythonURL)
      {
        packageOperationState = .preparingEnvironment
        if document.kernelSessionID != nil {
          try? await backend.closeSession(notebookURI: document.notebookURI)
          resetSessionState(to: .notStarted)
        }
        let pythonURL = try await packageManager.createEnvironment(
          at: environmentURL,
          basePythonURL: initialDetails.executableURL,
          workingDirectoryURL: workingDirectory
        )
        let candidate = PythonEnvironmentCandidate(
          executableURL: pythonURL,
          kind: packageEnvironmentScope == .shared
            ? .applicationSharedEnvironment : .projectManagedEnvironment)
        if !environmentCandidates.contains(where: { $0.id == candidate.id }) {
          environmentCandidates.insert(candidate, at: 0)
        }
        await selectPythonEnvironment(candidate)
        guard case .ready(let createdDetails, _) = environmentState else {
          throw NotebookPackageManagerError.processFailed(
            status: -1, message: "The new notebook environment could not be selected.")
        }
        targetDetails = createdDetails
      }

      packageOperationState = .installing(normalized)
      try await packageManager.install(
        requirements: normalized,
        pythonURL: targetDetails.executableURL,
        workspaceURL: workingDirectory
      )
      try? await managedEnvironmentStore.markUsed(
        scope: packageEnvironmentScope, workspaceURL: managedEnvironmentWorkspaceURL())
      packageOperationState = .succeeded(normalized)
      missingPackages.removeAll { missing in
        normalized.contains { requirement in
          requirement.localizedCaseInsensitiveCompare(missing) == .orderedSame
        }
      }
      await refreshInstalledPackages()
      await refreshManagedEnvironmentStorage()
    } catch {
      packageOperationState = .failed(error.localizedDescription)
    }
  }

  public func discoverPythonEnvironments(for notebookURL: URL) async {
    runOnceAuthorized = false
    executionFolderTrusted = false
    executionTrustPromptPresented = false
    installedPackages = []
    packagesLoaded = false
    packagesError = nil
    let workspace = managedEnvironmentWorkspaceURL(for: notebookURL)
    packageEnvironmentScope = await managedEnvironmentStore.scope(for: workspace)
    environmentCandidates = await environmentDiscovery.candidates(for: notebookURL)
    if let managed = await managedEnvironmentCandidate(
      scope: packageEnvironmentScope, workspaceURL: workspace)
    {
      environmentCandidates.removeAll { $0.executableURL == managed.executableURL }
      environmentCandidates.insert(managed, at: 0)
    } else {
      prioritizeBundledEnvironmentCandidate()
    }
    environmentAvailability = [:]
    guard let first = environmentCandidates.first else {
      environmentState = .notConfigured
      return
    }
    environmentState = .selected(
      first,
      workingDirectory: canonicalURL(notebookURL).deletingLastPathComponent()
    )
    // Disk usage is refreshed by Settings, not on the document-open critical path.
    managedEnvironmentSummaries = []
    managedPackageCacheSize = 0
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
    installedPackages = []
    packagesLoaded = false
    packagesError = nil
    if case .ready(let details) = environmentAvailability[candidate.id] {
      await activatePythonEnvironment(details)
      return
    }
    environmentState = .checking(candidate)
    environmentAvailability[candidate.id] = .checking
    do {
      let details = try await environmentPreflight.inspect(candidate)
      environmentAvailability[candidate.id] = .ready(details)
      await activatePythonEnvironment(details)
    } catch let failure as PythonPreflightFailure {
      environmentAvailability[candidate.id] = .unavailable(failure)
      environmentState = .invalid(candidate, failure)
    } catch {
      let failure = PythonPreflightFailure.launchFailed(error.localizedDescription)
      environmentAvailability[candidate.id] = .unavailable(failure)
      environmentState = .invalid(candidate, failure)
    }
  }

  private func activatePythonEnvironment(_ details: PythonEnvironmentDetails) async {
    if let sourceURL = document.sourceURL {
      let workspaceRoot = WorkspaceResolver.workspaceRoot(for: sourceURL)
      try? await environmentDiscovery.remember(details, for: workspaceRoot)
      environmentState = .ready(
        details,
        workingDirectory: canonicalURL(sourceURL).deletingLastPathComponent()
      )
      executionFolderTrusted = await folderTrustStore.isTrusted(
        folder: workspaceRoot,
        notebookURL: sourceURL
      )
    } else {
      try? FileManager.default.createDirectory(
        at: applicationWorkspaceDirectory, withIntermediateDirectories: true)
      environmentState = .ready(details, workingDirectory: applicationWorkspaceDirectory)
      executionFolderTrusted = true
    }
    if details.kind == .applicationSharedEnvironment
      || details.kind == .projectManagedEnvironment
    {
      try? await managedEnvironmentStore.markUsed(
        scope: details.kind == .applicationSharedEnvironment ? .shared : .project,
        workspaceURL: managedEnvironmentWorkspaceURL()
      )
      await refreshManagedEnvironmentStorage()
    }
    runOnceAuthorized = false
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
    if isApplicationManagedWorkingDirectory(workingDirectory) {
      executionFolderTrusted = true
      return true
    }
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
    if isApplicationManagedWorkingDirectory(workingDirectory) {
      executionFolderTrusted = true
      return true
    }
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

  private func isApplicationManagedWorkingDirectory(_ directory: URL) -> Bool {
    document.sourceURL == nil
      && canonicalURL(directory) == canonicalURL(applicationWorkspaceDirectory)
  }
}
