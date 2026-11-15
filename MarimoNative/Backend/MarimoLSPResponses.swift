import Foundation
import MarimoDomain

struct ConvertNotebookResult: Decodable {
  let source: String
}

struct PythonCompletionResponse: Decodable {
  let items: [PythonCompletionItem]
}

struct SessionListResponse: Codable {
  let sessions: [MarimoSessionInfo]
}

struct ListPackagesResponse: Codable {
  let packages: [NotebookPackage]
}

struct CellReplayResponse: Codable {
  let cells: [CellReplayRecord]
}

struct CellReplayRecord: Codable {
  let kind: String
  let notification: CellReplayNotification
  let executedSource: String?

  enum CodingKeys: String, CodingKey {
    case kind, notification
    case executedSource = "executedSource"
  }
}

struct CellReplayNotification: Codable {
  let payload: [String: JSONValue]

  init(from decoder: Decoder) throws {
    var object = try [String: JSONValue](from: decoder)
    object.removeValue(forKey: "op")
    payload = object
  }

  func encode(to encoder: Encoder) throws {
    var object = payload
    object["op"] = .string("cell-op")
    try object.encode(to: encoder)
  }
}
