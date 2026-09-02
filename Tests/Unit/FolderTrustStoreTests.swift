import Foundation
import MarimoEnvironment
import Testing

private struct FixedFolderMetadataProvider: FolderSecurityMetadataProviding {
  let value: FolderSecurityMetadata

  func metadata(folder _: URL, notebookURL _: URL?) -> FolderSecurityMetadata { value }
}

@Suite("Execution folder trust", .serialized)
struct FolderTrustStoreTests {
  @Test("A local folder identity persists in Application Support")
  func localFolderPersistence() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-trust-system-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.appending(path: "workspace")
    let support = root.appending(path: "support")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    let notebook = workspace.appending(path: "notebook.py")
    try Data("value = 1\n".utf8).write(to: notebook)
    let store = FolderTrustStore(applicationSupportDirectory: support)

    try await store.trust(folder: workspace, notebookURL: notebook)

    let reopened = FolderTrustStore(applicationSupportDirectory: support)
    #expect(await reopened.isTrusted(folder: workspace, notebookURL: notebook))
    let metadata = try await reopened.securityMetadata(folder: workspace, notebookURL: notebook)
    #expect(metadata.identity.canonicalPath == canonicalURL(workspace).path)
    #expect(metadata.isLocalVolume)
    #expect(!metadata.notebookIsQuarantined)
  }

  @Test("Folder trust requires path, volume, and resource identity")
  func identityNotPathAlone() async throws {
    let support = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-trust-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: support) }
    let path = "/tmp/workspace"
    let original = FolderSecurityMetadata(
      identity: FolderIdentity(
        canonicalPath: path, volumeIdentifier: 10, fileResourceIdentifier: 20
      ),
      isLocalVolume: true,
      notebookIsQuarantined: false
    )
    let trustedStore = FolderTrustStore(
      applicationSupportDirectory: support,
      metadataProvider: FixedFolderMetadataProvider(value: original)
    )
    try await trustedStore.trust(folder: URL(fileURLWithPath: path), notebookURL: nil)
    #expect(await trustedStore.isTrusted(folder: URL(fileURLWithPath: path), notebookURL: nil))

    let replaced = FolderSecurityMetadata(
      identity: FolderIdentity(
        canonicalPath: path, volumeIdentifier: 10, fileResourceIdentifier: 21
      ),
      isLocalVolume: true,
      notebookIsQuarantined: false
    )
    let reopenedStore = FolderTrustStore(
      applicationSupportDirectory: support,
      metadataProvider: FixedFolderMetadataProvider(value: replaced)
    )
    #expect(!(await reopenedStore.isTrusted(folder: URL(fileURLWithPath: path), notebookURL: nil)))
  }

  @Test("Remote and quarantined notebooks never reuse folder trust")
  func unsafeLocationsRequireReevaluation() async throws {
    let support = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-trust-unsafe-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: support) }
    let identity = FolderIdentity(
      canonicalPath: "/tmp/workspace", volumeIdentifier: 1, fileResourceIdentifier: 2
    )
    for metadata in [
      FolderSecurityMetadata(
        identity: identity, isLocalVolume: false, notebookIsQuarantined: false
      ),
      FolderSecurityMetadata(
        identity: identity, isLocalVolume: true, notebookIsQuarantined: true
      ),
    ] {
      let store = FolderTrustStore(
        applicationSupportDirectory: support,
        metadataProvider: FixedFolderMetadataProvider(value: metadata)
      )
      try await store.trust(folder: URL(fileURLWithPath: identity.canonicalPath), notebookURL: nil)
      #expect(
        !(await store.isTrusted(
          folder: URL(fileURLWithPath: identity.canonicalPath), notebookURL: nil
        ))
      )
    }
  }
}
