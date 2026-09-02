import Foundation
import MarimoDomain

public enum WebOutputKind: String, Sendable, Equatable {
  case html
  case markdown
  case svg
  case latex
  case vega
}

public struct WebOutputPayload: Sendable, Equatable {
  public let kind: WebOutputKind
  public let content: String
  public let allowsJavaScript: Bool
  public let displaySize: OutputDisplaySize?

  public init(
    kind: WebOutputKind,
    content: String,
    allowsJavaScript: Bool,
    displaySize: OutputDisplaySize?
  ) {
    self.kind = kind
    self.content = content
    self.allowsJavaScript = allowsJavaScript
    self.displaySize = displaySize
  }
}

public enum WebOutputSanitizer {
  public static func markdown(_ source: String) -> String {
    "<pre><code>\(escapeHTML(source))</code></pre>"
  }

  public static func svg(_ source: String) throws -> String {
    let decoded = decodeDataURL(source)
    let document: XMLDocument
    do {
      document = try XMLDocument(
        xmlString: decoded,
        options: [.nodeLoadExternalEntitiesNever, .nodePreserveAll]
      )
    } catch {
      throw WebOutputSanitizationError.invalidSVG
    }
    guard let root = document.rootElement(), localName(root) == "svg" else {
      throw WebOutputSanitizationError.invalidSVG
    }
    sanitize(root)
    return root.xmlString(options: [.nodeCompactEmptyElement])
  }

  public static func escapeHTML(_ source: String) -> String {
    source
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  private static let disallowedElements: Set<String> = [
    "script", "style", "foreignobject", "iframe", "object", "embed", "audio", "video",
  ]

  private static func sanitize(_ element: XMLElement) {
    for attribute in element.attributes ?? [] {
      let name = attribute.name?.lowercased() ?? ""
      let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let lowerValue = value.lowercased()
      let isEvent = name.hasPrefix("on")
      let isExternalReference =
        (name == "href" || name.hasSuffix(":href"))
        && !(value.hasPrefix("#") || lowerValue.hasPrefix("data:image/"))
      let isUnsafeValue =
        lowerValue.contains("javascript:")
        || (lowerValue.contains("url(") && !lowerValue.contains("url(#"))
      if name == "style" || isEvent || isExternalReference || isUnsafeValue {
        element.removeAttribute(forName: attribute.name ?? name)
      }
    }

    for child in element.children ?? [] {
      guard let childElement = child as? XMLElement else {
        if child.kind != .text { child.detach() }
        continue
      }
      if disallowedElements.contains(localName(childElement)) {
        childElement.detach()
      } else {
        sanitize(childElement)
      }
    }
  }

  private static func localName(_ element: XMLElement) -> String {
    let name = element.name?.lowercased() ?? ""
    return name.split(separator: ":").last.map(String.init) ?? name
  }

  private static func decodeDataURL(_ source: String) -> String {
    guard source.hasPrefix("data:image/svg+xml") else { return source }
    guard let comma = source.firstIndex(of: ",") else { return source }
    let header = source[..<comma]
    let payload = String(source[source.index(after: comma)...])
    if header.contains(";base64"), let data = Data(base64Encoded: payload) {
      return String(decoding: data, as: UTF8.self)
    }
    return payload.removingPercentEncoding ?? payload
  }
}

public enum WebOutputSanitizationError: Error, Sendable, Equatable {
  case invalidSVG
}
