import CoreGraphics
import Foundation
import MarimoDomain

public struct JSONOutlineNode: Sendable, Equatable, Identifiable {
  public let id: String
  public let label: String
  public let value: String?
  public let children: [JSONOutlineNode]

  public init(id: String, label: String, value: String?, children: [JSONOutlineNode] = []) {
    self.id = id
    self.label = label
    self.value = value
    self.children = children
  }
}

public struct StructuredOutputError: Sendable, Equatable, Identifiable {
  public let id: Int
  public let kind: String
  public let message: String
  public let line: Int?

  public init(id: Int, kind: String, message: String, line: Int?) {
    self.id = id
    self.kind = kind
    self.message = message
    self.line = line
  }
}

public struct TracebackLine: Sendable, Equatable, Identifiable {
  public let id: Int
  public let text: String
  public let fileURL: URL?
  public let line: Int?

  public init(id: Int, text: String, fileURL: URL?, line: Int?) {
    self.id = id
    self.text = text
    self.fileURL = fileURL
    self.line = line
  }
}

public struct CSVTable: Sendable, Equatable {
  public let columns: [String]
  public let rows: [[String]]

  public init(columns: [String], rows: [[String]]) {
    self.columns = columns
    self.rows = rows
  }
}

public struct DecodedOutputImage: @unchecked Sendable {
  public let image: CGImage
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(image: CGImage) {
    self.image = image
    pixelWidth = image.width
    pixelHeight = image.height
  }
}

public enum PreparedOutput: Sendable {
  case text(String, masked: Bool)
  case json(JSONOutlineNode)
  case errors([StructuredOutputError])
  case traceback([TracebackLine])
  case image(DecodedOutputImage)
  case csv(CSVTable)
  case nativeHTML(String)
  case mimeBundle(ResolvedMIMEBundle)
  case web(WebOutputPayload)
  case unsupported(mimeType: String, size: Int, raw: String)
  case failure(mimeType: String, message: String, size: Int, raw: String)
}
