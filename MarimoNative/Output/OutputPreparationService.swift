import Foundation
import ImageIO
import MarimoDomain
import MarimoWidgets

public actor OutputPreparationService {
  public static let shared = OutputPreparationService()

  private let registry: OutputRendererRegistry
  private let cache: OutputAssetCache

  public init(
    registry: OutputRendererRegistry = OutputRendererRegistry(),
    cache: OutputAssetCache = .shared
  ) {
    self.registry = registry
    self.cache = cache
  }

  public func prepare(_ output: MarimoOutput) async -> PreparedOutput {
    let kind = registry.renderer(for: output.mimeType)
    let key = cacheKey(for: output)
    if kind == .image, let cached = await cache.value(for: key) { return cached }
    let prepared = await Task.detached(priority: .userInitiated) {
      Self.prepareSynchronously(output, renderer: kind)
    }.value
    if case .image(let image) = prepared {
      let pixels = image.pixelWidth.multipliedReportingOverflow(by: image.pixelHeight)
      let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
      await cache.insert(
        prepared,
        for: key,
        cost: pixels.overflow || bytes.overflow ? Int.max : bytes.partialValue
      )
    }
    return prepared
  }

  public nonisolated static func prepareSynchronously(
    _ output: MarimoOutput,
    renderer: OutputRendererKind? = nil
  ) -> PreparedOutput {
    let selected = renderer ?? OutputRendererRegistry().renderer(for: output.mimeType)
    let raw = rawString(output.data)
    do {
      switch selected {
      case .text:
        guard case .string(let text) = output.data else {
          throw OutputPreparationError.expectedString
        }
        return .text(text, masked: output.mimeType == "text/password")
      case .json:
        let value: JSONValue
        if case .string(let string) = output.data {
          value = try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
        } else {
          value = output.data
        }
        var remainingNodes = 100_000
        return .json(
          outline(
            value,
            label: "root",
            path: "root",
            depth: 0,
            remainingNodes: &remainingNodes
          )
        )
      case .error:
        return .errors(try structuredErrors(output.data))
      case .traceback:
        guard case .string(let text) = output.data else {
          throw OutputPreparationError.expectedString
        }
        return .traceback(tracebackLines(from: stripHTML(text)))
      case .image:
        guard case .string(let encoded) = output.data,
          let data = imageData(from: encoded),
          let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { throw OutputPreparationError.invalidImage }
        guard imageDimensionsAreSafe(source),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw OutputPreparationError.invalidImage }
        return .image(DecodedOutputImage(image: image))
      case .csv:
        guard case .string(let text) = output.data else {
          throw OutputPreparationError.expectedString
        }
        return .csv(CSVStreamingParser.parse(text))
      case .html:
        guard case .string(let html) = output.data else {
          throw OutputPreparationError.expectedString
        }
        if let slider = MarimoComponentDecoder.slider(from: html) {
          return .slider(slider)
        }
        if let nativeText = HTMLNativeSubsetDecoder.decode(html) {
          return .nativeHTML(nativeText)
        }
        return .web(
          WebOutputPayload(
            kind: .html,
            content: html,
            allowsJavaScript: false,
            displaySize: output.displaySize
          )
        )
      case .mimeBundle:
        return .mimeBundle(try MIMEBundleResolver.resolve(output))
      case .webFallback:
        return .web(try webPayload(for: output, raw: raw))
      case .failure:
        guard case .object(let object) = output.data else {
          throw OutputPreparationError.invalidFailurePayload
        }
        let recoverable = object["raw"] ?? output.data
        return .failure(
          mimeType: output.mimeType,
          message: string(object["message"]) ?? "Output decoding failed.",
          size: recoverable.estimatedUTF8ByteCount(upTo: Int.max),
          raw: rawString(recoverable)
        )
      case .unsupported:
        return .unsupported(mimeType: output.mimeType, size: output.estimatedByteCount, raw: raw)
      }
    } catch {
      return .failure(
        mimeType: output.mimeType,
        message: String(describing: error),
        size: output.estimatedByteCount,
        raw: raw
      )
    }
  }

  private nonisolated static func webPayload(
    for output: MarimoOutput,
    raw: String
  ) throws -> WebOutputPayload {
    let mime = output.mimeType.lowercased()
    switch mime {
    case "text/markdown":
      guard case .string(let source) = output.data else {
        throw OutputPreparationError.expectedString
      }
      return WebOutputPayload(
        kind: .markdown,
        content: WebOutputSanitizer.markdown(source),
        allowsJavaScript: false,
        displaySize: output.displaySize
      )
    case "image/svg+xml":
      guard case .string(let source) = output.data else {
        throw OutputPreparationError.expectedString
      }
      return WebOutputPayload(
        kind: .svg,
        content: try WebOutputSanitizer.svg(source),
        allowsJavaScript: false,
        displaySize: output.displaySize
      )
    case "text/latex":
      guard case .string(let source) = output.data else {
        throw OutputPreparationError.expectedString
      }
      return WebOutputPayload(
        kind: .latex,
        content: source,
        allowsJavaScript: true,
        displaySize: output.displaySize
      )
    case "application/vnd.vegalite.v6+json", "application/vnd.vegalite.v5+json",
      "application/vnd.vega.v6+json", "application/vnd.vega.v5+json":
      return WebOutputPayload(
        kind: .vega,
        content: raw,
        allowsJavaScript: true,
        displaySize: output.displaySize
      )
    default:
      throw OutputPreparationError.unsupportedWebMIME
    }
  }

  private func cacheKey(for output: MarimoOutput) -> String {
    var hasher = Hasher()
    hasher.combine(output.mimeType)
    hasher.combine(Self.rawString(output.data))
    return String(hasher.finalize())
  }

  private nonisolated static func rawString(_ value: JSONValue) -> String {
    if case .string(let string) = value { return string }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value) else { return String(describing: value) }
    return String(decoding: data, as: UTF8.self)
  }

  private nonisolated static func outline(
    _ value: JSONValue,
    label: String,
    path: String,
    depth: Int,
    remainingNodes: inout Int
  ) -> JSONOutlineNode {
    guard depth < 64, remainingNodes > 0 else {
      return JSONOutlineNode(id: path, label: label, value: "…")
    }
    remainingNodes -= 1
    switch value {
    case .null: return JSONOutlineNode(id: path, label: label, value: "null")
    case .bool(let value): return JSONOutlineNode(id: path, label: label, value: String(value))
    case .integer(let value): return JSONOutlineNode(id: path, label: label, value: String(value))
    case .number(let value): return JSONOutlineNode(id: path, label: label, value: String(value))
    case .string(let value): return JSONOutlineNode(id: path, label: label, value: value)
    case .array(let values):
      var children: [JSONOutlineNode] = []
      for (index, child) in values.enumerated() where remainingNodes > 0 {
        children.append(
          outline(
            child,
            label: "[\(index)]",
            path: "\(path).\(index)",
            depth: depth + 1,
            remainingNodes: &remainingNodes
          )
        )
      }
      return JSONOutlineNode(
        id: path,
        label: label,
        value: "[\(values.count)]",
        children: children
      )
    case .object(let object):
      var children: [JSONOutlineNode] = []
      for key in object.keys.sorted() where remainingNodes > 0 {
        children.append(
          outline(
            object[key] ?? .null,
            label: key,
            path: "\(path).\(key)",
            depth: depth + 1,
            remainingNodes: &remainingNodes
          )
        )
      }
      return JSONOutlineNode(
        id: path,
        label: label,
        value: "{\(object.count)}",
        children: children
      )
    }
  }

  private nonisolated static func structuredErrors(
    _ value: JSONValue
  ) throws -> [StructuredOutputError] {
    guard case .array(let values) = value else { throw OutputPreparationError.expectedErrorArray }
    return values.enumerated().map { index, value in
      guard case .object(let object) = value else {
        return StructuredOutputError(id: index, kind: "error", message: rawString(value), line: nil)
      }
      return StructuredOutputError(
        id: index,
        kind: string(object["type"]) ?? string(object["error_type"]) ?? "error",
        message: string(object["msg"]) ?? "Unknown execution error",
        line: integer(object["lineno"])
      )
    }
  }

  private nonisolated static func tracebackLines(from text: String) -> [TracebackLine] {
    text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
      let text = String(line)
      let components = text.components(separatedBy: "\"")
      let path = components.count >= 3 ? components[1] : nil
      let lineNumber = text.range(of: "line ").flatMap { range -> Int? in
        let suffix = text[range.upperBound...]
        return Int(suffix.prefix { $0.isNumber })
      }
      return TracebackLine(
        id: index,
        text: text,
        fileURL: path.map { URL(fileURLWithPath: $0) },
        line: lineNumber
      )
    }
  }

  private nonisolated static func stripHTML(_ text: String) -> String {
    var result = ""
    var insideTag = false
    for character in text {
      if character == "<" {
        insideTag = true
        continue
      }
      if character == ">" {
        insideTag = false
        continue
      }
      if !insideTag { result.append(character) }
    }
    return
      result
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
  }

  private nonisolated static func imageData(from text: String) -> Data? {
    let payload = text.range(of: ";base64,").map { String(text[$0.upperBound...]) } ?? text
    return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
  }

  private nonisolated static func imageDimensionsAreSafe(_ source: CGImageSource) -> Bool {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else { return false }
    let pixels = width.int64Value.multipliedReportingOverflow(by: height.int64Value)
    return !pixels.overflow && pixels.partialValue > 0 && pixels.partialValue <= 100_000_000
  }

  private nonisolated static func string(_ value: JSONValue?) -> String? {
    guard case .string(let value)? = value else { return nil }
    return value
  }

  private nonisolated static func integer(_ value: JSONValue?) -> Int? {
    switch value {
    case .integer(let value): return Int(exactly: value)
    case .number(let value): return Int(exactly: value)
    default: return nil
    }
  }
}

public enum OutputPreparationError: Error, Sendable, Equatable {
  case expectedString
  case expectedErrorArray
  case invalidImage
  case invalidFailurePayload
  case unsupportedWebMIME
}

public enum CSVStreamingParser {
  public static func parse(_ source: String) -> CSVTable {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var iterator = source.makeIterator()
    var pending: Character?

    while let character = pending ?? iterator.next() {
      pending = nil
      if quoted {
        if character == "\"" {
          if let next = iterator.next() {
            if next == "\"" {
              field.append("\"")
            } else {
              quoted = false
              pending = next
            }
          } else {
            quoted = false
          }
        } else {
          field.append(character)
        }
      } else {
        switch character {
        case "\"" where field.isEmpty:
          quoted = true
        case ",":
          row.append(field)
          field = ""
        case "\n":
          row.append(field)
          rows.append(row)
          row = []
          field = ""
        case "\r":
          break
        default:
          field.append(character)
        }
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    guard let header = rows.first else { return CSVTable(columns: [], rows: []) }
    return CSVTable(columns: header, rows: Array(rows.dropFirst()))
  }
}
