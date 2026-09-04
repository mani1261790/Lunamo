import Foundation
import MarimoBackend
import MarimoDomain
import Testing

@testable import MarimoApplication

@Suite("Notebook panels")
struct NotebookPanelTests {
  @Test("File tree is read-only filtered and does not follow symlinks")
  func fileTreeFiltering() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "x = 1".write(to: root.appending(path: "notebook.py"), atomically: true, encoding: .utf8)
    try "a,b".write(to: root.appending(path: "data.csv"), atomically: true, encoding: .utf8)
    try "ignore".write(to: root.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "linked.py"),
      withDestinationURL: root.appending(path: "notebook.py")
    )

    let files = NotebookFileTree.load(root: root)
    #expect(files.map(\.name) == ["data.csv", "notebook.py"])
    #expect(files.first(where: { $0.name == "notebook.py" })?.kind == .notebook)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "notes.txt").path))
  }

  @Test("Cell summary uses first non-empty source line")
  func cellSidebarSummary() {
    #expect(NotebookCellState(code: "\n  value = 42\nprint(value)").sidebarSummary == "value = 42")
    #expect(NotebookCellState(code: " \n\t").sidebarSummary == "Empty cell")
  }

  @Test("Variable notifications merge metadata and bounded kernel previews")
  @MainActor
  func variableNotificationMerge() {
    let store = NotebookStore(backend: PlaceholderMarimoBackend())
    store.applyVariableNotification(
      [
        "variables": .array([
          .object([
            "name": .string("answer"),
            "declared_by": .array([.string("cell-a")]),
            "used_by": .array([.string("cell-b")]),
          ])
        ])
      ],
      includesValues: false
    )
    store.applyVariableNotification(
      [
        "variables": .array([
          .object([
            "name": .string("answer"), "datatype": .string("int"),
            "value": .string(String(repeating: "あ", count: 2_000)),
          ])
        ])
      ],
      includesValues: true
    )

    #expect(store.variables.count == 1)
    #expect(store.variables[0].declaredBy == ["cell-a"])
    #expect(store.variables[0].usedBy == ["cell-b"])
    #expect(store.variables[0].datatype == "int")
    #expect(
      (store.variables[0].preview?.utf8.count ?? 0) <= NotebookVariableState.maximumPreviewBytes
    )
  }

  @Test("Document syntax state gates execution")
  @MainActor
  func invalidDocumentDisablesExecution() {
    #expect(NotebookStore.executionAllowed(openState: .idle, hasCells: true))
    #expect(
      !NotebookStore.executionAllowed(
        openState: .invalidSyntax(URL(fileURLWithPath: "/tmp/bad.py"), line: 1, column: 1),
        hasCells: true
      ))
  }

  @Test("Panel UI uses native containers and avoids editor glass")
  func nativePanelArchitecture() throws {
    let root = repositoryRoot()
    let rootView = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookRootView.swift"),
      encoding: .utf8)
    let sidebar = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Sidebar/NotebookSidebarView.swift"),
      encoding: .utf8)
    let inspector = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Inspector/NotebookInspectorView.swift"),
      encoding: .utf8)
    let cell = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellView.swift"), encoding: .utf8)
    #expect(rootView.contains("NavigationSplitView"))
    #expect(rootView.contains("ScrollViewReader"))
    #expect(sidebar.contains("OutlineGroup"))
    #expect(sidebar.contains(".navigationTitle(\"Files\")"))
    #expect(sidebar.contains(".accessibilityLabel(\"Files\")"))
    #expect(!sidebar.contains("Section(\"Cells\")"))
    #expect(!sidebar.contains("selectedCellBinding"))
    #expect(!sidebar.contains("localizedSummary"))
    #expect(!sidebar.contains(".accessibilityLabel(\"Cells\")"))
    #expect(inspector.contains("Section(\"Session\")"))
    #expect(inspector.contains("Section(\"Variables\")"))
    #expect(!rootView.contains("glassEffect"))
    #expect(!cell.contains("glassEffect"))
    for forbidden in ["Git", "Terminal", "Extension", "AI Assistant"] {
      #expect(!rootView.contains(forbidden))
      #expect(!sidebar.contains(forbidden))
    }
  }

  @Test("Inspector is hidden by default and remains available on demand")
  @MainActor
  func inspectorStartsHidden() {
    let store = NotebookStore(backend: PlaceholderMarimoBackend())
    #expect(!store.inspectorPresented)
  }

  @Test("English and Japanese UI localization ship together")
  func localizationResources() throws {
    let root = repositoryRoot().appending(path: "MarimoNative/Resources/Localization")
    let english = try String(
      contentsOf: root.appending(path: "en.lproj/Localizable.strings"), encoding: .utf8)
    let japanese = try String(
      contentsOf: root.appending(path: "ja.lproj/Localizable.strings"), encoding: .utf8)
    for key in [
      "Open Notebook…", "Run All", "Interrupt", "Files", "Cells", "Session", "Variables",
      "Export HTML…", "Export ipynb…", "Export Markdown…", "Open Logs…",
      "Review Logs Before Export", "Export Reviewed Logs…",
    ] {
      #expect(english.contains("\"\(key)\" ="))
      #expect(japanese.contains("\"\(key)\" ="))
    }
    #expect(japanese.contains("\"Run All\" = \"すべて実行\""))
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
