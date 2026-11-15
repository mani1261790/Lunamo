import Foundation
import MarimoDomain

public struct NotebookSidebarFile: Identifiable, Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case directory
    case notebook
    case data
    case image
  }

  public let url: URL
  public let kind: Kind
  public let children: [NotebookSidebarFile]?

  public var id: URL { url }
  public var name: String { url.lastPathComponent }

  public init(url: URL, kind: Kind, children: [NotebookSidebarFile]? = nil) {
    self.url = url
    self.kind = kind
    self.children = children
  }
}

public enum NotebookFileTree {
  public static let visibleExtensions = Set([
    "py", "csv", "json", "png", "jpg", "jpeg", "gif", "webp", "svg",
  ])

  public static func load(root: URL, maximumDepth: Int = 12) -> [NotebookSidebarFile] {
    scan(root: root.standardizedFileURL, depth: 0, maximumDepth: maximumDepth)
  }

  private static func scan(root: URL, depth: Int, maximumDepth: Int) -> [NotebookSidebarFile] {
    guard depth < maximumDepth else { return [] }
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true,
        values.isSymbolicLink != true
      else { return nil }
      if values.isDirectory == true {
        let children = scan(root: url, depth: depth + 1, maximumDepth: maximumDepth)
        return NotebookSidebarFile(url: url, kind: .directory, children: children)
      }
      let pathExtension = url.pathExtension.lowercased()
      guard visibleExtensions.contains(pathExtension) else { return nil }
      let kind: NotebookSidebarFile.Kind
      switch pathExtension {
      case "py": kind = .notebook
      case "csv", "json": kind = .data
      default: kind = .image
      }
      return NotebookSidebarFile(url: url, kind: kind)
    }
    .sorted {
      if ($0.kind == .directory) != ($1.kind == .directory) {
        return $0.kind == .directory
      }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

public struct NotebookVariableState: Identifiable, Sendable, Equatable {
  public static let maximumPreviewBytes = 4 * 1_024

  public let name: String
  public var declaredBy: [String]
  public var usedBy: [String]
  public var datatype: String?
  public var preview: String?

  public var id: String { name }

  public init(
    name: String,
    declaredBy: [String] = [],
    usedBy: [String] = [],
    datatype: String? = nil,
    preview: String? = nil
  ) {
    self.name = name
    self.declaredBy = declaredBy
    self.usedBy = usedBy
    self.datatype = datatype
    self.preview = Self.truncatedPreview(preview)
  }

  public static func truncatedPreview(_ value: String?) -> String? {
    guard let value else { return nil }
    let bytes = Array(value.utf8)
    guard bytes.count > maximumPreviewBytes else { return value }
    let suffix = "…"
    var end = maximumPreviewBytes - suffix.utf8.count
    while end > 0, String(bytes: bytes[..<end], encoding: .utf8) == nil { end -= 1 }
    return String(decoding: bytes[..<end], as: UTF8.self) + suffix
  }
}

extension NotebookCellState {
  public var sidebarSummary: String {
    code.split(whereSeparator: { $0.isNewline })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty }) ?? "Empty cell"
  }
}

extension NotebookStore {
  func cellIndex(_ cellID: UUID) -> Int? {
    document.cells.firstIndex { $0.runtimeID == cellID }
  }

  public var documentAllowsExecution: Bool {
    Self.executionAllowed(openState: openState, hasCells: !document.cells.isEmpty)
  }

  public static func executionAllowed(openState: OpenState, hasCells: Bool) -> Bool {
    guard hasCells else { return false }
    switch openState {
    case .invalidSyntax, .convertible, .failed, .loading: return false
    case .idle, .loaded: return true
    }
  }

  public var notebookDirectoryURL: URL? {
    document.sourceURL?.deletingLastPathComponent() ?? applicationWorkspaceDirectory
  }

  public func refreshSidebarFiles() async {
    guard let root = notebookDirectoryURL else {
      sidebarFiles = []
      return
    }
    sidebarFiles = await Task.detached { NotebookFileTree.load(root: root) }.value
  }

  public func openSidebarFile(_ file: NotebookSidebarFile) async {
    guard file.kind == .notebook else { return }
    await open(file.url)
  }

  func applyVariableNotification(_ payload: [String: JSONValue], includesValues: Bool) {
    guard case .array(let items)? = payload["variables"] else { return }
    var byName = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0) })
    for item in items {
      guard case .object(let object) = item, let name = object.string(for: "name") else { continue }
      var variable = byName[name] ?? NotebookVariableState(name: name)
      if includesValues {
        variable.datatype = object.string(for: "datatype")
        variable.preview = NotebookVariableState.truncatedPreview(object.string(for: "value"))
      } else {
        variable.declaredBy = object.strings(for: "declared_by")
        variable.usedBy = object.strings(for: "used_by")
      }
      byName[name] = variable
    }
    variables = byName.values.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  fileprivate func strings(for key: String) -> [String] {
    guard case .array(let values)? = self[key] else { return [] }
    return values.compactMap { value in
      switch value {
      case .string(let string): string
      case .integer(let integer): String(integer)
      default: nil
      }
    }
  }
}
