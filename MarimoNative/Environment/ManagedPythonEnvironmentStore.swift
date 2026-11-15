import CryptoKit
import Foundation

public enum ManagedPythonEnvironmentScope: String, Codable, Sendable, CaseIterable, Equatable {
  case shared
  case project

  public var displayName: String {
    switch self {
    case .shared: "Shared Environment"
    case .project: "This Project"
    }
  }
}

public struct ManagedPythonEnvironmentSummary: Sendable, Equatable, Identifiable {
  public let id: String
  public let scope: ManagedPythonEnvironmentScope
  public let environmentURL: URL
  public let sizeBytes: Int64
  public let lastUsedAt: Date?
  public let exists: Bool
  public let isCurrent: Bool

  public init(
    id: String,
    scope: ManagedPythonEnvironmentScope,
    environmentURL: URL,
    sizeBytes: Int64,
    lastUsedAt: Date?,
    exists: Bool,
    isCurrent: Bool
  ) {
    self.id = id
    self.scope = scope
    self.environmentURL = environmentURL
    self.sizeBytes = sizeBytes
    self.lastUsedAt = lastUsedAt
    self.exists = exists
    self.isCurrent = isCurrent
  }
}

public actor ManagedPythonEnvironmentStore {
  private struct Registry: Codable {
    var projectScopes: [String: ManagedPythonEnvironmentScope] = [:]
    var lastUsed: [String: Date] = [:]
  }

  public let rootURL: URL
  public let uvCacheURL: URL
  private let registryURL: URL
  private let fileManager: FileManager

  public init(applicationSupportDirectory: URL? = nil, fileManager: FileManager = .default) {
    let support =
      applicationSupportDirectory
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appending(path: "MarimoNative", directoryHint: .isDirectory)
    rootURL = support.appending(path: "Python Environments", directoryHint: .isDirectory)
    uvCacheURL = support.appending(path: "Package Cache/uv", directoryHint: .isDirectory)
    registryURL = support.appending(path: "managed-environments.json")
    self.fileManager = fileManager
  }

  public func scope(for workspaceURL: URL) -> ManagedPythonEnvironmentScope {
    load().projectScopes[workspaceKey(workspaceURL)] ?? .shared
  }

  public func setScope(_ scope: ManagedPythonEnvironmentScope, for workspaceURL: URL) throws {
    var registry = load()
    let key = workspaceKey(workspaceURL)
    if scope == .shared {
      registry.projectScopes.removeValue(forKey: key)
    } else {
      registry.projectScopes[key] = scope
    }
    try persist(registry)
  }

  public func environmentURL(
    for scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL
  ) -> URL {
    switch scope {
    case .shared:
      rootURL.appending(path: "shared-v1", directoryHint: .isDirectory)
    case .project:
      rootURL.appending(
        path: "projects/\(workspaceKey(workspaceURL))", directoryHint: .isDirectory)
    }
  }

  public func pythonURL(
    for scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL
  ) -> URL {
    environmentURL(for: scope, workspaceURL: workspaceURL).appending(path: "bin/python")
  }

  public func markUsed(
    scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL,
    at date: Date = Date()
  ) throws {
    var registry = load()
    registry.lastUsed[environmentID(scope: scope, workspaceURL: workspaceURL)] = date
    try persist(registry)
  }

  public func summaries(
    for workspaceURL: URL,
    currentScope: ManagedPythonEnvironmentScope
  ) -> [ManagedPythonEnvironmentSummary] {
    let registry = load()
    return ManagedPythonEnvironmentScope.allCases.map { scope in
      let id = environmentID(scope: scope, workspaceURL: workspaceURL)
      let url = environmentURL(for: scope, workspaceURL: workspaceURL)
      var isDirectory: ObjCBool = false
      let exists =
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        && isDirectory.boolValue
      return ManagedPythonEnvironmentSummary(
        id: id,
        scope: scope,
        environmentURL: url,
        sizeBytes: exists ? directorySize(url) : 0,
        lastUsedAt: registry.lastUsed[id],
        exists: exists,
        isCurrent: scope == currentScope
      )
    }
  }

  public func uvCacheSize() -> Int64 {
    directorySize(uvCacheURL)
  }

  @discardableResult
  public func moveEnvironmentToTrash(
    scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL
  ) throws -> URL? {
    let url = environmentURL(for: scope, workspaceURL: workspaceURL)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    var resultingURL: NSURL?
    try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    var registry = load()
    registry.lastUsed.removeValue(forKey: environmentID(scope: scope, workspaceURL: workspaceURL))
    try persist(registry)
    return resultingURL as URL?
  }

  public func moveUnusedProjectEnvironmentsToTrash(
    olderThan cutoff: Date,
    excluding workspaceURL: URL
  ) throws -> Int {
    let projectsURL = rootURL.appending(path: "projects", directoryHint: .isDirectory)
    let currentID = workspaceKey(workspaceURL)
    let registry = load()
    let children =
      (try? fileManager.contentsOfDirectory(
        at: projectsURL,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    var removed = 0
    for url in children where url.lastPathComponent != currentID {
      let id = "project:\(url.lastPathComponent)"
      let lastUsed =
        registry.lastUsed[id]
        ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      guard lastUsed < cutoff else { continue }
      var resultingURL: NSURL?
      try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
      removed += 1
    }
    return removed
  }

  public func clearUVCache() throws {
    guard fileManager.fileExists(atPath: uvCacheURL.path) else { return }
    var resultingURL: NSURL?
    try fileManager.trashItem(at: uvCacheURL, resultingItemURL: &resultingURL)
  }

  private func environmentID(
    scope: ManagedPythonEnvironmentScope,
    workspaceURL: URL
  ) -> String {
    switch scope {
    case .shared: "shared-v1"
    case .project: "project:\(workspaceKey(workspaceURL))"
    }
  }

  private func workspaceKey(_ url: URL) -> String {
    let digest = SHA256.hash(data: Data(canonicalURL(url).path.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func load() -> Registry {
    guard let data = try? Data(contentsOf: registryURL) else { return Registry() }
    return (try? JSONDecoder().decode(Registry.self, from: data)) ?? Registry()
  }

  private func persist(_ registry: Registry) throws {
    try fileManager.createDirectory(
      at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(registry).write(to: registryURL, options: [.atomic])
  }

  private func directorySize(_ url: URL) -> Int64 {
    guard
      let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return 0 }
    var result: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard
        let values = try? fileURL.resourceValues(forKeys: [
          .isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey,
        ]), values.isRegularFile == true
      else { continue }
      result += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
    return result
  }
}
