import Foundation

public enum JSONRPCFramingError: Error, Sendable, Equatable {
  case protocolTextOutsideFrame
  case headerTooLarge
  case nonASCIIHeader
  case missingContentLength
  case duplicateContentLength
  case invalidContentLength
  case payloadTooLarge
  case invalidUTF8
}

public struct JSONRPCFramer: Sendable {
  public static let maximumPayloadBytes = 64 * 1024 * 1024
  private static let maximumHeaderBytes = 8 * 1024
  private static let separator = Data([13, 10, 13, 10])
  private static let requiredPrefix = Data("Content-Length:".utf8)

  private var buffer = Data()
  private var expectedPayloadBytes: Int?

  public init() {}

  public mutating func append(_ bytes: Data) throws -> [Data] {
    buffer.append(bytes)
    var payloads: [Data] = []
    while true {
      if expectedPayloadBytes == nil {
        try validatePrefix()
        guard let separatorRange = buffer.range(of: Self.separator) else {
          if buffer.count > Self.maximumHeaderBytes { throw JSONRPCFramingError.headerTooLarge }
          return payloads
        }
        let headerData = buffer[..<separatorRange.lowerBound]
        guard let header = String(data: headerData, encoding: .ascii) else {
          throw JSONRPCFramingError.nonASCIIHeader
        }
        expectedPayloadBytes = try Self.contentLength(in: header)
        buffer.removeSubrange(..<separatorRange.upperBound)
      }

      guard let length = expectedPayloadBytes, buffer.count >= length else { return payloads }
      let payload = Data(buffer.prefix(length))
      guard String(data: payload, encoding: .utf8) != nil else {
        throw JSONRPCFramingError.invalidUTF8
      }
      buffer.removeFirst(length)
      expectedPayloadBytes = nil
      payloads.append(payload)
      if buffer.isEmpty { return payloads }
    }
  }

  public static func frame(_ payload: Data) throws -> Data {
    guard payload.count <= maximumPayloadBytes else { throw JSONRPCFramingError.payloadTooLarge }
    guard String(data: payload, encoding: .utf8) != nil else {
      throw JSONRPCFramingError.invalidUTF8
    }
    var result = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
    result.append(payload)
    return result
  }

  private mutating func validatePrefix() throws {
    let comparableCount = min(buffer.count, Self.requiredPrefix.count)
    guard comparableCount > 0 else { return }
    let received = buffer.prefix(comparableCount)
    let expected = Self.requiredPrefix.prefix(comparableCount)
    guard received.elementsEqual(expected) else {
      throw JSONRPCFramingError.protocolTextOutsideFrame
    }
  }

  private static func contentLength(in header: String) throws -> Int {
    let lines = header.components(separatedBy: "\r\n")
    let values = lines.compactMap { line -> String? in
      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
      return parts[1].trimmingCharacters(in: .whitespaces)
    }
    guard !values.isEmpty else { throw JSONRPCFramingError.missingContentLength }
    guard values.count == 1 else { throw JSONRPCFramingError.duplicateContentLength }
    let value = values[0]
    guard !value.isEmpty, value.allSatisfy(\.isNumber), let length = Int(value) else {
      throw JSONRPCFramingError.invalidContentLength
    }
    guard length <= maximumPayloadBytes else { throw JSONRPCFramingError.payloadTooLarge }
    return length
  }
}
