import Foundation

public enum HTMLNativeSubsetDecoder {
  private static let allowedElements: Set<String> = [
    "html", "head", "body", "pre", "code", "span", "br",
  ]

  public static func decode(_ source: String) -> String? {
    guard !source.isEmpty,
      let document = try? XMLDocument(
        xmlString: source,
        options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
      ),
      let root = document.rootElement()
    else { return nil }
    var rendered = ""
    guard append(root, to: &rendered) else { return nil }
    return rendered.trimmingCharacters(in: .newlines)
  }

  private static func append(_ node: XMLNode, to rendered: inout String) -> Bool {
    switch node.kind {
    case .text:
      rendered.append(node.stringValue ?? "")
      return true
    case .document:
      return appendChildren(of: node, to: &rendered)
    case .element:
      guard let element = node as? XMLElement,
        let name = element.name?.lowercased(),
        allowedElements.contains(name),
        (element.attributes ?? []).allSatisfy({
          !($0.name?.lowercased().hasPrefix("on") ?? false)
        })
      else { return false }
      if name == "head" { return element.stringValue?.isEmpty == true }
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
    default:
      return false
    }
  }

  private static func appendChildren(of node: XMLNode, to rendered: inout String) -> Bool {
    for child in node.children ?? [] {
      guard append(child, to: &rendered) else { return false }
    }
    return true
  }
}
