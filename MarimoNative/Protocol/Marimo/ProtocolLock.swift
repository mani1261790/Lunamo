public struct ProtocolLock: Codable, Sendable, Equatable {
  public let marimoLSPCommit: String
  public let marimoLSPVersion: String
  public let marimoBaseVersion: String
  public let kernelMarimoVersion: String
  public let marimoSourceCommit: String
  public let ownedDocumentVersion: String
  public let commandMethod: String
  public let notificationMethod: String
  public let schemaHash: String
  public let generatedAt: String
}
