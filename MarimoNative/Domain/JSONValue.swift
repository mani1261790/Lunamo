import Foundation

public enum JSONValue: Codable, Sendable, Equatable, Hashable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .null:
      hasher.combine(0)
    case .bool(let value):
      hasher.combine(1)
      hasher.combine(value)
    case .integer(let value):
      hasher.combine(2)
      hasher.combine(value)
    case .number(let value):
      hasher.combine(3)
      hasher.combine(value)
    case .string(let value):
      hasher.combine(4)
      hasher.combine(value)
    case .array(let values):
      hasher.combine(5)
      hasher.combine(values)
    case .object(let values):
      hasher.combine(6)
      for key in values.keys.sorted() {
        hasher.combine(key)
        hasher.combine(values[key])
      }
    }
  }
}
