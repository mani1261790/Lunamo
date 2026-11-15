import CryptoKit
import Darwin
import Foundation

public struct SavedEnvironmentSelection: Codable, Sendable, Equatable {
  public let executableURL: URL
  public let identity: ExecutableIdentity

  public init(executableURL: URL, identity: ExecutableIdentity) {
    self.executableURL = executableURL
    self.identity = identity
  }
}

public actor WorkspaceEnvironmentStore {
  private let fileURL: URL

  public init(applicationSupportDirectory: URL? = nil) {
    let base = applicationSupportDirectory ?? Self.defaultApplicationSupportDirectory
    fileURL = base.appending(path: "workspace-environments.json")
  }

  public func selection(for workspaceRoot: URL) -> SavedEnvironmentSelection? {
    load()[Self.workspaceKey(workspaceRoot)]
  }

  public func save(_ selection: SavedEnvironmentSelection, for workspaceRoot: URL) throws {
    var selections = load()
    selections[Self.workspaceKey(workspaceRoot)] = selection
    try persist(selections)
  }

  private func load() -> [String: SavedEnvironmentSelection] {
    guard let data = try? Data(contentsOf: fileURL) else { return [:] }
    return (try? JSONDecoder().decode([String: SavedEnvironmentSelection].self, from: data)) ?? [:]
  }

  private func persist(_ selections: [String: SavedEnvironmentSelection]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(selections)
    try data.write(to: fileURL, options: [.atomic])
  }

  private static func workspaceKey(_ url: URL) -> String {
    canonicalURL(url).path
  }

  private static var defaultApplicationSupportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "MarimoNative", directoryHint: .isDirectory)
  }
}

public enum WorkspaceResolver {
  private static let rootMarkers = [".git", "pyproject.toml", "uv.lock"]

  public static func workspaceRoot(for notebookURL: URL) -> URL {
    let notebookDirectory = canonicalURL(notebookURL).deletingLastPathComponent()
    var directory = notebookDirectory
    while directory.path != "/" {
      if rootMarkers.contains(where: {
        FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
      }) {
        return directory
      }
      directory.deleteLastPathComponent()
    }
    return notebookDirectory
  }
}

public func canonicalURL(_ url: URL) -> URL {
  url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
}

public func normalizedExecutableURL(_ url: URL) -> URL {
  url.standardizedFileURL
}

public func executableIdentity(at url: URL) throws -> ExecutableIdentity {
  let canonical = canonicalURL(url)
  var information = stat()
  let status = canonical.withUnsafeFileSystemRepresentation { path in
    path.map { Darwin.lstat($0, &information) } ?? -1
  }
  guard status == 0, information.st_mode & S_IFMT == S_IFREG,
    FileManager.default.isExecutableFile(atPath: canonical.path)
  else { throw PythonPreflightFailure.missingExecutable(canonical) }
  let contents = try Data(contentsOf: canonical, options: [.mappedIfSafe])
  return ExecutableIdentity(
    canonicalPath: canonical.path,
    volumeIdentifier: UInt64(information.st_dev),
    fileIdentifier: UInt64(information.st_ino),
    modificationSeconds: Int64(information.st_mtimespec.tv_sec),
    modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec),
    size: Int64(information.st_size),
    contentSHA256: SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
  )
}

public actor PythonEnvironmentDiscovery {
  private let store: WorkspaceEnvironmentStore
  private let searchSystem: Bool
  private let bundledPythonURL: URL?

  public init(
    store: WorkspaceEnvironmentStore = WorkspaceEnvironmentStore(), searchSystem: Bool = true,
    bundledPythonURL: URL? = nil
  ) {
    self.store = store
    self.searchSystem = searchSystem
    self.bundledPythonURL = bundledPythonURL
  }

  public func candidates(for notebookURL: URL) async -> [PythonEnvironmentCandidate] {
    let notebookDirectory = canonicalURL(notebookURL).deletingLastPathComponent()
    let workspaceRoot = WorkspaceResolver.workspaceRoot(for: notebookURL)
    var candidates: [PythonEnvironmentCandidate] = []
    appendIfExecutable(
      notebookDirectory.appending(path: ".venv/bin/python"),
      kind: .notebookVirtualEnvironment,
      to: &candidates
    )
    if workspaceRoot != notebookDirectory {
      appendIfExecutable(
        workspaceRoot.appending(path: ".venv/bin/python"),
        kind: .workspaceVirtualEnvironment,
        to: &candidates
      )
    }
    if let saved = await store.selection(for: workspaceRoot),
      (try? executableIdentity(at: saved.executableURL)) == saved.identity
    {
      candidates.append(
        PythonEnvironmentCandidate(
          executableURL: normalizedExecutableURL(saved.executableURL),
          kind: .savedWorkspaceSelection,
          expectedIdentity: saved.identity
        )
      )
    }
    if let bundledPythonURL {
      appendIfExecutable(bundledPythonURL, kind: .bundled, to: &candidates)
    }
    if searchSystem {
      let home = FileManager.default.homeDirectoryForCurrentUser
      var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
      directories += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(
        String.init
      ).filter { $0.hasPrefix("/") }
      for root in [
        home.appending(path: ".pyenv/versions"), home.appending(path: ".local/share/uv/python"),
        home.appending(path: "miniconda3/envs"), home.appending(path: "anaconda3/envs"),
        URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions"),
      ] {
        let children =
          (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))
          ?? []
        directories += children.sorted { $0.path < $1.path }.prefix(64).map {
          $0.appending(path: "bin").path
        }
      }
      directories += ["miniconda3/bin", "anaconda3/bin", "miniforge3/bin"].map {
        home.appending(path: $0).path
      }
      for directory in Set(directories).sorted() {
        for name in [
          "python", "python3", "python3.14", "python3.13", "python3.12", "python3.11", "python3.10",
        ] {
          appendIfExecutable(
            URL(fileURLWithPath: directory).appending(path: name), kind: .detected, to: &candidates)
        }
      }
    }
    var seen: Set<String> = []
    return candidates.filter {
      let identity =
        $0.kind == .detected
        ? "detected:\(canonicalURL($0.executableURL).path)"
        : "\($0.kind.rawValue):\(normalizedExecutableURL($0.executableURL).path)"
      return seen.insert(identity).inserted
    }
  }

  public func remember(_ details: PythonEnvironmentDetails, for workspaceRoot: URL) async throws {
    try await store.save(
      SavedEnvironmentSelection(executableURL: details.executableURL, identity: details.identity),
      for: workspaceRoot
    )
  }

  private func appendIfExecutable(
    _ url: URL,
    kind: PythonEnvironmentKind,
    to candidates: inout [PythonEnvironmentCandidate]
  ) {
    guard let identity = try? executableIdentity(at: url) else { return }
    candidates.append(
      PythonEnvironmentCandidate(
        executableURL: normalizedExecutableURL(url),
        kind: kind,
        expectedIdentity: identity
      )
    )
  }
}
