import Foundation

public enum OutputChannel: String, Codable, Sendable, Equatable, CaseIterable {
  case stdout
  case stderr
  case stdin
  case pdb
  case output
  case marimoError = "marimo-error"
  case media
}

public struct MarimoOutput: Codable, Sendable, Equatable {
  public static let payloadByteLimit = 128 * 1_024 * 1_024

  public let channel: OutputChannel
  public let mimeType: String
  public let data: JSONValue
  public let timestamp: Double?
  public let displaySize: OutputDisplaySize?

  public init(
    channel: OutputChannel,
    mimeType: String,
    data: JSONValue,
    timestamp: Double? = nil,
    displaySize: OutputDisplaySize? = nil
  ) {
    self.channel = channel
    self.mimeType = mimeType
    self.data = data
    self.timestamp = timestamp
    self.displaySize = displaySize
  }

  enum CodingKeys: String, CodingKey {
    case channel
    case mimeType = "mimetype"
    case data
    case timestamp
    case displaySize
  }

  public static func decodeWireValue(
    _ value: JSONValue,
    payloadByteLimit: Int = Self.payloadByteLimit
  ) throws -> MarimoOutput {
    guard value.estimatedUTF8ByteCount(upTo: payloadByteLimit + 1) <= payloadByteLimit else {
      throw MarimoOutputDecodingError.payloadTooLarge(limit: payloadByteLimit)
    }
    guard case .object(let object) = value,
      case .string(let rawChannel)? = object["channel"],
      let channel = OutputChannel(rawValue: rawChannel),
      case .string(let mimeType)? = object["mimetype"],
      let data = object["data"]
    else { throw MarimoOutputDecodingError.invalidWireValue }
    switch data {
    case .string, .array, .object:
      let timestamp: Double?
      switch object["timestamp"] {
      case .number(let value): timestamp = value
      case .integer(let value): timestamp = Double(value)
      case nil, .null: timestamp = nil
      default: throw MarimoOutputDecodingError.invalidWireValue
      }
      return MarimoOutput(
        channel: channel,
        mimeType: mimeType,
        data: data,
        timestamp: timestamp,
        displaySize: nil
      )
    case .null, .bool, .integer, .number:
      throw MarimoOutputDecodingError.unsupportedDataShape
    }
  }

  public static func displayFailure(
    _ error: Error,
    rawValue: JSONValue,
    channel: OutputChannel = .output
  ) -> MarimoOutput {
    MarimoOutput(
      channel: channel,
      mimeType: "application/vnd.marimonative+renderer-error",
      data: .object([
        "message": .string(String(describing: error)),
        "raw": rawValue,
      ])
    )
  }

  public var estimatedByteCount: Int {
    data.estimatedUTF8ByteCount(upTo: Int.max)
  }

  public var estimatedLineCount: Int {
    guard case .string(let text) = data else { return 1 }
    return max(
      1,
      text.reduce(into: 1) { count, character in
        if character == "\n" { count += 1 }
      })
  }
}

public struct OutputDisplaySize: Codable, Sendable, Equatable {
  public let width: Double?
  public let height: Double?

  public init(width: Double?, height: Double?) {
    self.width = width
    self.height = height
  }
}

public enum MarimoOutputDecodingError: Error, Sendable, Equatable {
  case payloadTooLarge(limit: Int)
  case invalidWireValue
  case unsupportedDataShape
}

extension JSONValue {
  public func estimatedUTF8ByteCount(upTo limit: Int) -> Int {
    func adding(_ lhs: Int, _ rhs: Int) -> Int {
      if lhs >= limit || rhs >= limit - lhs { return limit }
      return lhs + rhs
    }

    func encodedStringSize(_ value: String) -> Int {
      var total = 2
      for scalar in value.unicodeScalars {
        let size: Int
        switch scalar.value {
        case 0x22, 0x5C, 0x08, 0x0C, 0x0A, 0x0D, 0x09:
          size = 2
        case 0...0x1F:
          size = 6
        default:
          size = String(scalar).utf8.count
        }
        total = adding(total, size)
        if total >= limit { return limit }
      }
      return total
    }

    switch self {
    case .null:
      return 4
    case .bool(let value):
      return value ? 4 : 5
    case .integer(let value):
      return String(value).utf8.count
    case .number(let value):
      return String(value).utf8.count
    case .string(let value):
      return encodedStringSize(value)
    case .array(let values):
      var total = 2
      for value in values {
        total = adding(total, value.estimatedUTF8ByteCount(upTo: limit))
        total = adding(total, 1)
        if total >= limit { return limit }
      }
      return total
    case .object(let object):
      var total = 2
      for (key, value) in object {
        total = adding(total, encodedStringSize(key) + 1)
        total = adding(total, value.estimatedUTF8ByteCount(upTo: limit))
        total = adding(total, 1)
        if total >= limit { return limit }
      }
      return total
    }
  }
}
