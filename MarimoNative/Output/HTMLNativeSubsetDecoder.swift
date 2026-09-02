import Foundation
import SwiftSoup

public enum HTMLNativeSubsetDecoder {
  private static let allowedElements: Set<String> = [
    "pre", "code", "span", "br",
  ]

  public static func decode(_ source: String) -> String? {
    guard !source.isEmpty,
      let document = try? SwiftSoup.parseBodyFragment(source),
      let body = document.body()
    else { return nil }
    var rendered = ""
    guard appendChildren(of: body, to: &rendered) else { return nil }
    return rendered.trimmingCharacters(in: .newlines)
  }

  private static func append(_ node: Node, to rendered: inout String) -> Bool {
    if let text = node as? TextNode {
      rendered.append(text.getWholeText())
      return true
    }
    guard let element = node as? Element else { return false }
    let name = element.tagNameNormal()
    guard allowedElements.contains(name),
      (element.getAttributes()?.asList() ?? []).allSatisfy({
        !$0.getKey().lowercased().hasPrefix("on")
      })
    else { return false }
    if name == "br" {
      rendered.append("\n")
      return true
    }
    let start = rendered.endIndex
    guard appendChildren(of: element, to: &rendered) else { return false }
    if name == "pre", rendered.endIndex > start, !rendered.hasSuffix("\n") {
      rendered.append("\n")
    }
    return true
  }

  private static func appendChildren(of node: Node, to rendered: inout String) -> Bool {
    for child in node.getChildNodes() {
      guard append(child, to: &rendered) else { return false }
    }
    return true
  }
}
