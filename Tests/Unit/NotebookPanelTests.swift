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
    let settings = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookSettingsView.swift"),
      encoding: .utf8)
    let commands = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookMenuCommands.swift"),
      encoding: .utf8)
    let insertionBar = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellInsertionBar.swift"),
      encoding: .utf8)
    let assistant = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookAssistantView.swift"),
      encoding: .utf8)
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
    #expect(settings.contains("Form"))
    #expect(settings.contains("Section(\"Python Execution\")"))
    #expect(settings.contains("Section(\"Packages\")"))
    #expect(settings.contains("refreshInstalledPackages"))
    #expect(settings.contains("Choose Python Executable…"))
    #expect(settings.contains("Choose Working Directory…"))
    #expect(commands.contains("Find in Selected Cell"))
    #expect(commands.contains(".keyboardShortcut(\"f\", modifiers: [.command])"))
    #expect(rootView.contains("insertionBar(at: 0)"))
    #expect(insertionBar.contains("Insert Code Cell"))
    #expect(insertionBar.contains(".dropDestination(for: String.self)"))
    #expect(cell.contains(".draggable(cell.runtimeID.uuidString)"))
    #expect(cell.contains("Duplicate Cell"))
    #expect(cell.contains("Delete Cell"))
    #expect(rootView.contains("Notebook Assistant"))
    #expect(assistant.contains("SystemLanguageModel.default"))
    #expect(assistant.contains("supportsLocale(Locale(identifier: \"ja\"))"))
    #expect(assistant.contains("Replace Selected Cell"))
    #expect(!assistant.contains("requestRun"))
    #expect(!assistant.contains("save()"))
    for forbidden in ["Git", "Terminal", "Extension"] {
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
      "Python Execution", "Execution Safety", "Choose Python Executable…",
      "Choose Working Directory…", "Check Again", "Ready", "Settings…",
      "Find in Selected Cell",
      "Insert Code Cell", "Drag Cell to Reorder", "Move Cell Up", "Move Cell Down",
      "Duplicate Cell", "Delete Cell",
      "Packages", "Refresh", "No package list loaded.",
      "Installed in the selected Python environment",
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
