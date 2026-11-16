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
    let rootView = try [
      "MarimoNative/UI/Notebook/NotebookRootView.swift",
      "MarimoNative/UI/Notebook/NotebookRootToolbar.swift",
    ].map { try String(contentsOf: root.appending(path: $0), encoding: .utf8) }.joined(
      separator: "\n")
    let sidebar = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Sidebar/NotebookSidebarView.swift"),
      encoding: .utf8)
    let cell = try [
      "MarimoNative/UI/Cell/CellView.swift", "MarimoNative/UI/Cell/CellExecutionControls.swift",
    ].map { try String(contentsOf: root.appending(path: $0), encoding: .utf8) }.joined(
      separator: "\n")
    let cellCursorCoordinator = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellCursorCoordinator.swift"),
      encoding: .utf8)
    let cellCursorBehavior = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellCursorBehavior.swift"),
      encoding: .utf8)
    let settingsCore = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookSettingsView.swift"),
      encoding: .utf8)
    let packageSettings = try String(
      contentsOf: root.appending(
        path: "MarimoNative/UI/Notebook/NotebookPackageSettingsView.swift"),
      encoding: .utf8)
    let settings = settingsCore + packageSettings
    let executionSetup = try String(
      contentsOf: root.appending(
        path: "MarimoNative/UI/Notebook/NotebookExecutionSetupViews.swift"),
      encoding: .utf8)
    let commands = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookMenuCommands.swift"),
      encoding: .utf8)
    let insertionBar = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellInsertionBar.swift"),
      encoding: .utf8)
    let markdownView = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/MarkdownDocumentView.swift"),
      encoding: .utf8)
    let assistantCore = try [
      "MarimoNative/UI/Notebook/NotebookAssistantView.swift",
      "MarimoNative/UI/Notebook/NotebookAssistantConversation.swift",
    ].map { try String(contentsOf: root.appending(path: $0), encoding: .utf8) }.joined(
      separator: "\n")
    let assistantSuggestion = try String(
      contentsOf: root.appending(
        path: "MarimoNative/UI/Notebook/NotebookAssistantSuggestionView.swift"),
      encoding: .utf8)
    let assistant = assistantCore + assistantSuggestion
    let checkedEdit = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/NotebookCheckedCodeEdit.swift"),
      encoding: .utf8)
    let terminal = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookTerminalView.swift"),
      encoding: .utf8)
    let terminalConsole = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/TerminalConsoleView.swift"),
      encoding: .utf8)
    #expect(rootView.contains("NotebookWorkspaceLayout"))
    #expect(rootView.contains("ScrollViewReader"))
    #expect(sidebar.contains("OutlineGroup"))
    #expect(sidebar.contains(".accessibilityLabel(\"Files\")"))
    #expect(!sidebar.contains("Section(\"Cells\")"))
    #expect(!sidebar.contains("selectedCellBinding"))
    #expect(!sidebar.contains("localizedSummary"))
    #expect(!sidebar.contains(".accessibilityLabel(\"Cells\")"))
    #expect(rootView.contains("assistantPresented"))
    #expect(rootView.contains("NotebookAssistantView"))
    #expect(!rootView.contains("NotebookInspectorView"))
    #expect(!rootView.contains("Toggle Inspector"))
    // Panel boundaries and resize behavior are covered by hosted workspace tests.
    #expect(!rootView.contains("glassEffect"))
    #expect(!cell.contains("glassEffect"))
    #expect(settings.contains("Form"))
    #expect(settings.contains("Section(\"Current Environment\")"))
    #expect(settings.contains("Text(\"Ready to Use\")"))
    #expect(settings.contains("Text(\"Needs Setup\")"))
    #expect(settings.contains("environmentOverview"))
    #expect(settings.contains("Text(\"Environment Strategy\")"))
    #expect(settings.contains("Section(\"Environment in Use\")"))
    #expect(settings.contains("Section(\"Managed Storage\")"))
    #expect(settings.contains("ManagedPythonEnvironmentScope.shared"))
    #expect(settings.contains("store.removeManagedEnvironment(environmentActionScope)"))
    #expect(settings.contains("Image(systemName: \"magnifyingglass\")"))
    #expect(
      settings.contains(".background(Color(nsColor: .controlBackgroundColor), in: Capsule())"))
    #expect(settings.contains(".focused($packageFilterFocused)"))
    #expect(settings.contains("Clear Package Filter"))
    #expect(settings.contains("packageRequirementFocused"))
    #expect(settings.contains("PackageSettingsButtonStyle(prominent: true)"))
    #expect(settings.contains("PackageSettingsButtonStyle(iconOnly: true)"))
    #expect(settings.contains(".accessibilityLabel(\"Refresh\")"))
    #expect(settings.contains("environmentAvailability"))
    #expect(settings.contains("candidate.kind == .bundled"))
    #expect(settings.contains("refreshInstalledPackages"))
    #expect(settings.contains("Choose Python Executable…"))
    #expect(settings.contains("Choose Working Directory…"))
    #expect(settings.contains("Choose Folder…"))
    #expect(settings.contains("needsWorkingDirectory"))
    #expect(settings.contains("Required before Run"))
    #expect(settings.contains("SettingsActionButtonStyle"))
    #expect(settings.contains("Capsule(style: .continuous)"))
    #expect(settings.contains("ViewThatFits(in: .horizontal)"))
    #expect(settings.contains("manualSetupActions(axis: .horizontal)"))
    #expect(settings.contains("Section(\"Notebook Storage\")"))
    #expect(settings.contains("Default App Folder"))
    #expect(executionSetup.contains("workingFolderGuidance"))
    #expect(executionSetup.contains("NotebookEnvironmentActions.chooseWorkingDirectory"))
    #expect(rootView.contains("runDisabledHelp: runDisabledHelp"))
    #expect(cell.contains(".help(executionControlHelp)"))
    #expect(cell.contains("cell.runtime.successfullyExecuted(cell.code)"))
    #expect(cell.contains("if executionControlHovered { return \"play.fill\" }"))
    #expect(cell.contains("executionControlHovered ? \"stop.fill\" : \"progress.indicator\""))
    #expect(cell.contains("return \"exclamationmark.triangle.fill\""))
    #expect(cell.contains("return completedCurrentSource ? \"checkmark\" : \"play.fill\""))
    #expect(
      cell.contains(
        "cell.runtime.hasExecutionError || cell.runtime.status == .disabledTransitively"))
    #expect(cell.contains("ProgressView()"))
    #expect(rootView.contains("tracksReorderFrame: draggedCellID != nil"))
    #expect(commands.contains("Find in Selected Cell"))
    #expect(commands.contains(".keyboardShortcut(\"f\", modifiers: [.command])"))
    #expect(rootView.contains("insertionBar(at: 0)"))
    #expect(insertionBar.contains("Insert Code Cell"))
    #expect(insertionBar.contains("localizedUI(\"Code\")"))
    #expect(insertionBar.contains("localizedUI(\"Text\")"))
    #expect(insertionBar.contains("CellInsertionButtonStyle"))
    #expect(insertionBar.contains("Capsule(style: .continuous)"))
    #expect(insertionBar.contains(".opacity(hovering || reorderTargeted ? 1 : 0)"))
    #expect(!insertionBar.contains(".buttonStyle(.bordered)"))
    #expect(insertionBar.contains("reorderTargeted"))
    #expect(cell.contains("LongPressGesture"))
    #expect(cell.contains(".offset(y: reorderOffset.height)"))
    #expect(cellCursorCoordinator.contains("NSCursor.closedHand.push()"))
    #expect(cellCursorCoordinator.contains("NSCursor.openHand.push()"))
    #expect(cellCursorBehavior.contains("cellHovered && !editorHovered"))
    #expect(cell.contains(".onHover"))
    #expect(!cell.contains("onContinuousHover"))
    #expect(cellCursorCoordinator.contains("NSCursor.pop()"))
    #expect(!cell.contains(".draggable("))
    #expect(!cell.contains("line.3.horizontal"))
    #expect(cell.contains("textCell(markdown:"))
    #expect(cell.contains("MarkdownDocumentView(source: markdown)"))
    #expect(cell.contains(".highPriorityGesture("))
    #expect(cell.contains("TapGesture(count: 2)"))
    #expect(cell.contains("@FocusState private var markdownEditorFocused"))
    #expect(cell.contains(".onChange(of: markdownEditorFocused)"))
    #expect(!cell.contains("Show Python"))
    #expect(!cell.contains("localizedUI(\"Preview\")"))
    #expect(!cell.contains("localizedUI(\"Edit\")"))
    #expect(cell.contains("if cellHovered"))
    #expect(cell.contains("if cell.editor.markdown == nil"))
    #expect(markdownView.contains("MarkdownDocumentParser.parse(source)"))
    #expect(markdownView.contains("inlineOnlyPreservingWhitespace"))
    #expect(cell.contains("Duplicate Cell"))
    #expect(cell.contains("Delete Cell"))
    #expect(rootView.contains("Notebook Assistant"))
    #expect(commands.contains("Toggle Assistant"))
    #expect(
      commands.contains(".keyboardShortcut(shortcuts.shortcut(for: .toggleAssistant)?.toSwiftUI)"))
    #expect(assistant.contains("SystemLanguageModel.default"))
    #expect(assistant.contains("Attach Selected Cell"))
    #expect(assistant.contains("Attach Files or Images"))
    #expect(assistant.contains("systemImage: \"paperclip\""))
    #expect(assistant.contains("systemImage: \"chevron.left.forwardslash.chevron.right\""))
    #expect(assistant.contains(".fileImporter("))
    #expect(assistant.contains("conversation.messages"))
    #expect(assistant.contains("clock.arrow.circlepath"))
    #expect(assistant.contains("conversation.startNewConversation()"))
    #expect(assistant.contains("conversation.restore(item)"))
    #expect(!assistant.contains("Close Assistant"))
    #expect(!assistant.contains("var close: () -> Void"))
    #expect(!rootView.contains(".sheet(isPresented: $assistantPresented)"))
    #expect(!assistant.contains("requestRun"))
    #expect(!assistant.contains("save()"))
    #expect(assistant.contains("Review Changes to Cell %ld"))
    #expect(assistant.contains("Apply to Cell"))
    #expect(assistant.contains("store.applyCheckedCodeEdit"))
    #expect(assistant.contains("expectedCode: suggestion.originalCode"))
    #expect(checkedEdit.contains("send(.updateCode"))
    #expect(!checkedEdit.contains("runCell"))
    #expect(!checkedEdit.contains("runAll"))
    #expect(rootView.contains("NotebookTerminalView"))
    #expect(rootView.contains("NotebookTerminalSplit"))
    #expect(rootView.contains("Notebook toolbar"))
    #expect(!rootView.contains("ToolbarItem(placement: .principal)"))
    #expect(terminal.contains("ContentUnavailableView"))
    #expect(terminal.contains("Name and Save…"))
    #expect(terminal.contains("TerminalConsoleView(session: session)"))
    #expect(!terminal.contains("TextField("))
    #expect(!terminal.contains("Enter a shell command"))
    #expect(terminalConsole.contains("TerminalTextView"))
    #expect(terminalConsole.contains("textView.editableStart"))
    #expect(terminalConsole.contains("submitHandler"))
    #expect(!cell.contains("Text(cell.editor.markdown == nil ? \"Code\" : \"Text\")"))
    #expect(!cell.contains("cellActionBar"))
    #expect(cell.contains("hoverActionBar"))
    #expect(cell.contains("Explain Error"))
    #expect(cell.contains("NotebookRuntimeErrorContext.runtimeErrorContext(for: cell) != nil"))
    #expect(rootView.contains("explainErrorWithAssistant"))
    #expect(assistant.contains("Latest runtime error:"))
    #expect(assistant.contains("store.leaveEditor()"))
    #expect(cell.contains(".padding(.trailing, 16)"))
    #expect(rootView.contains(".contextMenu"))
    #expect(rootView.contains("Button(\"Duplicate Cell\", systemImage: \"square.on.square\")"))
    #expect(
      rootView.contains("Button(\"Delete Cell\", systemImage: \"trash\", role: .destructive)"))
    for forbidden in ["Git", "Extension"] {
      #expect(!rootView.contains(forbidden))
      #expect(!sidebar.contains(forbidden))
    }
    #expect(!sidebar.contains("Terminal"))
    for localizedSource in [rootView, cell, settings, insertionBar, assistant, terminal] {
      #expect(
        !localizedSource.unicodeScalars.contains {
          (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
      )
    }
  }

  @Test("Assistant sidebar is hidden by default and remains available on demand")
  @MainActor
  func assistantStartsHidden() {
    let store = NotebookStore(backend: PlaceholderMarimoBackend())
    #expect(!store.assistantPresented)
  }

  @Test("English and Japanese UI localization ship together")
  func localizationResources() throws {
    let root = repositoryRoot().appending(path: "MarimoNative/Resources/Localization")
    let english = try String(
      contentsOf: root.appending(path: "en.lproj/Localizable.strings"), encoding: .utf8)
    let japanese = try String(
      contentsOf: root.appending(path: "ja.lproj/Localizable.strings"), encoding: .utf8)
    for key in [
      "Save changes before quitting?", "Save changes before closing?", "Don't Save",
      "Open Link in Browser?", "Run Python Code?", "Trust This Folder", "Run Once",
      "Choose Python Executable", "Choose Directory",
      "Open Notebook…", "Run All", "Interrupt", "Files", "Cells", "Session", "Variables",
      "Export HTML…", "Export ipynb…", "Export Markdown…", "Open Logs…",
      "Review Logs Before Export", "Export Reviewed Logs…",
      "Python Execution", "Execution Safety", "Choose Python Executable…",
      "Choose Working Directory…", "Check Again", "Ready", "Settings…",
      "Find in Selected Cell",
      "Code", "Text", "Markdown", "Markdown text editor", "Double-click to edit Markdown",
      "Insert Code Cell", "Drag Cell to Reorder", "Move Cell Up", "Move Cell Down",
      "Duplicate Cell", "Delete Cell",
      "Packages", "Refresh", "No package list loaded.",
      "Installed in the selected Python environment",
      "Detected Environments", "Environment Details", "Manual Setup", "Scan Again",
      "Python Check Failed", "Ready to Run", "Attach Selected Cell", "Attach Files or Images",
      "Move Here", "Terminal", "Toggle Terminal", "Name and Save…",
      "Open a marimo notebook or import a Jupyter/Python file.",
      "Import as marimo Notebook",
      "The source stays unchanged. Save the converted notebook as a separate Python file.",
      "Save and Open", "Choose a Different File",
      "The imported notebook cannot replace its source file.", "Choose Again",
      "Current Environment", "Ready to Use", "Needs Setup", "Built-in Python", "Recommended",
      "Needs marimo", "Unsupported", "Unavailable", "Checking requirements…",
      "Package Environment", "Installed Packages", "Package List Not Loaded",
      "Filter Packages", "No Ready Environment", "Show Environments",
      "Toggle Assistant",
      "Conversation History", "No Conversation History", "Untitled Conversation",
      "Start a new conversation to keep the current one in history.",
      "Review Changes to Cell %ld", "Apply to Cell", "Original", "Proposed",
      "The cell changed after this suggestion was generated.",
      "Choose Folder…", "Required before Run",
      "Choose a working folder before running this untitled notebook",
      "marimo 0.24.0 is not installed in this Python environment.",
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
