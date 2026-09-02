import Darwin
import Foundation

public struct FolderIdentity: Codable, Sendable, Equatable, Hashable {
  public let canonicalPath: String
  public let volumeIdentifier: UInt64
  public let fileResourceIdentifier: UInt64

  public init(
    canonicalPath: String,
    volumeIdentifier: UInt64,
    fileResourceIdentifier: UInt64
  ) {
    self.canonicalPath = canonicalPath
    self.volumeIdentifier = volumeIdentifier
    self.fileResourceIdentifier = fileResourceIdentifier
  }
}

public struct FolderSecurityMetadata: Sendable, Equatable {
  public let identity: FolderIdentity
  public let isLocalVolume: Bool
  public let notebookIsQuarantined: Bool

  public init(
    identity: FolderIdentity,
    isLocalVolume: Bool,
    notebookIsQuarantined: Bool
  ) {
    self.identity = identity
    self.isLocalVolume = isLocalVolume
    self.notebookIsQuarantined = notebookIsQuarantined
  }
}

public protocol FolderSecurityMetadataProviding: Sendable {
  func metadata(folder: URL, notebookURL: URL?) throws -> FolderSecurityMetadata
}

public struct SystemFolderSecurityMetadataProvider: FolderSecurityMetadataProviding {
  public init() {}

  public func metadata(folder: URL, notebookURL: URL?) throws -> FolderSecurityMetadata {
    let canonicalFolder = canonicalURL(folder)
    var information = stat()
    let status = canonicalFolder.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.lstat($0, &information) } ?? -1
    }
    guard status == 0, information.st_mode & S_IFMT == S_IFDIR else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    let values = try canonicalFolder.resourceValues(forKeys: [.volumeIsLocalKey])
    return FolderSecurityMetadata(
      identity: FolderIdentity(
        canonicalPath: canonicalFolder.path,
        volumeIdentifier: UInt64(information.st_dev),
        fileResourceIdentifier: UInt64(information.st_ino)
      ),
      isLocalVolume: values.volumeIsLocal == true,
      notebookIsQuarantined: notebookURL.map(Self.hasQuarantineAttribute) ?? false
    )
  }

  private static func hasQuarantineAttribute(_ url: URL) -> Bool {
    canonicalURL(url).withUnsafeFileSystemRepresentation { path in
      guard let path else { return false }
      return Darwin.getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }
  }
}

public actor FolderTrustStore {
  private let fileURL: URL
  private let metadataProvider: any FolderSecurityMetadataProviding

  public init(
    applicationSupportDirectory: URL? = nil,
    metadataProvider: any FolderSecurityMetadataProviding = SystemFolderSecurityMetadataProvider()
  ) {
    let base = applicationSupportDirectory ?? Self.defaultApplicationSupportDirectory
    fileURL = base.appending(path: "trusted-folders.json")
    self.metadataProvider = metadataProvider
  }

  public func trust(folder: URL, notebookURL: URL?) throws {
    let metadata = try metadataProvider.metadata(folder: folder, notebookURL: notebookURL)
    guard metadata.isLocalVolume, !metadata.notebookIsQuarantined else { return }
    var identities = load()
    identities.removeAll { $0.canonicalPath == metadata.identity.canonicalPath }
    identities.append(metadata.identity)
    try persist(identities)
  }

  public func isTrusted(folder: URL, notebookURL: URL?) -> Bool {
    guard let metadata = try? metadataProvider.metadata(folder: folder, notebookURL: notebookURL),
      metadata.isLocalVolume,
      !metadata.notebookIsQuarantined
    else { return false }
    return load().contains(metadata.identity)
  }

  public func securityMetadata(folder: URL, notebookURL: URL?) throws -> FolderSecurityMetadata {
    try metadataProvider.metadata(folder: folder, notebookURL: notebookURL)
  }

  private func load() -> [FolderIdentity] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([FolderIdentity].self, from: data)) ?? []
  }

  private func persist(_ identities: [FolderIdentity]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(identities).write(to: fileURL, options: [.atomic])
  }

  private static var defaultApplicationSupportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "MarimoNative", directoryHint: .isDirectory)
  }
}
