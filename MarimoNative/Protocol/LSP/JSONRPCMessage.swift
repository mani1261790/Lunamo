import Foundation
import MarimoDomain

public enum JSONRPCID: Codable, Sendable, Equatable, Hashable {
  case number(UInt64)
  case string(String)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(UInt64.self) {
      self = .number(number)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    }
  }
}

public struct JSONRPCErrorObject: Codable, Sendable, Equatable, Error {
  public let code: Int
  public let message: String
  public let data: JSONValue?

  public init(code: Int, message: String, data: JSONValue? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }
}

public enum JSONRPCMessage: Sendable, Equatable {
  case request(id: JSONRPCID, method: String, params: JSONValue?)
  case notification(method: String, params: JSONValue?)
  case response(id: JSONRPCID, result: JSONValue)
  case error(id: JSONRPCID?, error: JSONRPCErrorObject)
}

extension JSONRPCMessage: Codable {
  private enum CodingKeys: String, CodingKey {
    case jsonrpc, id, method, params, result, error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(String.self, forKey: .jsonrpc)
    guard version == "2.0" else {
      throw DecodingError.dataCorruptedError(
        forKey: .jsonrpc,
        in: container,
        debugDescription: "JSON-RPC version must be 2.0"
      )
    }
    if let method = try container.decodeIfPresent(String.self, forKey: .method) {
      let params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
      if let id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id) {
        self = .request(id: id, method: method, params: params)
      } else {
        self = .notification(method: method, params: params)
      }
      return
    }
    let id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
    if let error = try container.decodeIfPresent(JSONRPCErrorObject.self, forKey: .error) {
      self = .error(id: id, error: error)
    } else if let id {
      self = .response(
        id: id,
        result: try container.decodeIfPresent(JSONValue.self, forKey: .result) ?? .null
      )
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .id,
        in: container,
        debugDescription: "JSON-RPC response requires an id"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("2.0", forKey: .jsonrpc)
    switch self {
    case .request(let id, let method, let params):
      try container.encode(id, forKey: .id)
      try container.encode(method, forKey: .method)
      try container.encodeIfPresent(params, forKey: .params)
    case .notification(let method, let params):
      try container.encode(method, forKey: .method)
      try container.encodeIfPresent(params, forKey: .params)
    case .response(let id, let result):
      try container.encode(id, forKey: .id)
      try container.encode(result, forKey: .result)
    case .error(let id, let error):
      try container.encodeIfPresent(id, forKey: .id)
      if id == nil { try container.encodeNil(forKey: .id) }
      try container.encode(error, forKey: .error)
    }
  }
}
