import Foundation

public struct PythonCompletionItem: Codable, Sendable, Equatable, Identifiable {
  public let label: String
  public let detail: String?
  public let kind: String?

  public var id: String { "\(label)|\(kind ?? "")" }

  public init(label: String, detail: String? = nil, kind: String? = nil) {
    self.label = label
    self.detail = detail
    self.kind = kind
  }
}
