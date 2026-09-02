import Foundation
import Testing

@Suite("Architecture boundaries")
struct ArchitectureBoundaryTests {
  @Test("Views do not import transport or protocol modules")
  func viewsOnlyUseApplicationFacingModules() throws {
    let root = repositoryRoot()
    let uiRoot = root.appending(path: "MarimoNative/UI")
    let files = try swiftFiles(below: uiRoot)
    let forbiddenImports = ["MarimoBackend", "MarimoProcess", "MarimoProtocol"]

    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      for module in forbiddenImports {
        #expect(!source.contains("import \(module)"), "\(file.lastPathComponent) imports \(module)")
      }
    }
  }

  @Test("Production Swift avoids unsafe termination and casts")
  func productionCodeAvoidsForbiddenTokens() throws {
    let root = repositoryRoot()
    let sources = try swiftFiles(below: root.appending(path: "MarimoNative"))
    let forbiddenTokens = ["try!", "fatalError(", " as!"]

    for file in sources {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in forbiddenTokens {
        #expect(!source.contains(token), "\(file.lastPathComponent) contains \(token)")
      }
    }
  }

  @Test("Notebook canvas contains no browser or server runtime")
  func notebookCanvasIsNative() throws {
    let root = repositoryRoot()
    let notebookSources =
      try swiftFiles(below: root.appending(path: "MarimoNative/UI/Notebook"))
      + swiftFiles(below: root.appending(path: "MarimoNative/UI/Cell"))
    let forbiddenCanvasTokens = [
      "WKWebView", "WebView", "Electron", "Chromium", "React", "JupyterLab",
    ]
    for file in notebookSources {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in forbiddenCanvasTokens {
        #expect(!source.contains(token), "\(file.lastPathComponent) contains \(token)")
      }
    }

    let processSources = try swiftFiles(below: root.appending(path: "MarimoNative/Process"))
    for file in processSources {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in ["marimo edit", "marimo run", "http.server", "node "] {
        #expect(!source.contains(token), "\(file.lastPathComponent) launches \(token)")
      }
    }
  }

  @Test("Swift never generates marimo Python source with string templates")
  func swiftDoesNotGenerateMarimoSource() throws {
    let root = repositoryRoot()
    let sources = try swiftFiles(below: root.appending(path: "MarimoNative"))
    let forbiddenSourceFragments = ["@app.cell", "marimo.App(", "__generated_with", "app.run()"]
    for file in sources {
      let source = try String(contentsOf: file, encoding: .utf8)
      for fragment in forbiddenSourceFragments {
        #expect(!source.contains(fragment), "\(file.lastPathComponent) generates \(fragment)")
      }
    }
  }

  @Test("Notebook uses one outer scroll and a native TextKit 2 editor")
  func nativeEditorArchitecture() throws {
    let root = repositoryRoot()
    let notebook = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookRootView.swift"),
      encoding: .utf8
    )
    let cell = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellView.swift"),
      encoding: .utf8
    )
    let editor = try String(
      contentsOf: root.appending(path: "MarimoNative/Editor/CodeEditorView.swift"),
      encoding: .utf8
    )
    #expect(notebook.components(separatedBy: "ScrollView {").count - 1 == 1)
    #expect(notebook.contains("LazyVStack(spacing: 16)"))
    #expect(cell.contains("CodeEditorView("))
    #expect(!cell.contains("TextEditor("))
    #expect(!editor.contains("WKWebView"))
    #expect(editor.contains("NSTextContentStorage"))
    #expect(editor.contains("NSTextLayoutManager"))
  }

  @Test("Notebook layout follows the native split-view geometry")
  func nativeNotebookLayout() throws {
    let root = repositoryRoot()
    let app = try String(
      contentsOf: root.appending(path: "MarimoNative/App/MarimoNativeApp.swift"),
      encoding: .utf8
    )
    let notebook = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookRootView.swift"),
      encoding: .utf8
    )
    #expect(app.contains("Window(\"MarimoNative\", id: \"notebook\")"))
    #expect(!app.contains("WindowGroup"))
    #expect(app.contains("CommandGroup(replacing: .newItem)"))
    #expect(notebook.contains("NavigationSplitView"))
    #expect(notebook.contains("min: 180, ideal: 240, max: 360"))
    #expect(notebook.contains("min: 260, ideal: 300, max: 440"))
    #expect(notebook.contains("maxWidth: 1_100"))
    #expect(notebook.contains("minWidth: 960, idealWidth: 1_320, minHeight: 640"))
    #expect(notebook.contains("toggleSidebar"))
    #expect(notebook.contains("inspectorPresented"))
  }

  @Test("Cells expose non-color execution states without glass surfaces")
  func nativeCellAppearance() throws {
    let root = repositoryRoot()
    let cell = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellView.swift"),
      encoding: .utf8
    )
    for token in [
      "LazyVStack(spacing: 16)",
      ".padding(.horizontal, 16)",
      ".padding(.vertical, 12)",
      "if selected || hovering",
      "Label(\"Queued\", systemImage: \"clock\")",
      "Text(\"Running\")",
      "Label(\"Stale\", systemImage: \"clock.arrow.circlepath\")",
      "Label(\"Error\", systemImage: \"exclamationmark.triangle.fill\")",
      ".accessibilityValue",
    ] {
      let combined = cell + notebookSource(root)
      #expect(combined.contains(token), "Missing native cell appearance token: \(token)")
    }
    #expect(!cell.contains("glassEffect"))
  }

  @Test("Native output stays lazy, recoverable, accessible, and off the MainActor")
  func nativeOutputArchitecture() throws {
    let root = repositoryRoot()
    let output = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Output/OutputView.swift"),
      encoding: .utf8
    )
    let preparation = try String(
      contentsOf: root.appending(path: "MarimoNative/Output/OutputPreparationService.swift"),
      encoding: .utf8
    )
    let cache = try String(
      contentsOf: root.appending(path: "MarimoNative/Output/OutputAssetCache.swift"),
      encoding: .utf8
    )
    for token in [
      "Copy Raw Data", "Save Raw Data", "Label(\"Stale\"", "Label(\"Running\"",
      ".accessibilityValue", "CSVTableView", "JSONOutlineView",
    ] {
      #expect(output.contains(token), "Missing native output token: \(token)")
    }
    #expect(preparation.contains("Task.detached"))
    #expect(preparation.contains("CGImageSourceCreateImageAtIndex"))
    #expect(preparation.contains("CSVStreamingParser.parse"))
    #expect(cache.contains("entries.min"))
    #expect(!output.contains("WKWebView"))
  }

  @Test("Every specified notebook shortcut has a native menu command")
  func notebookShortcutsAreDiscoverable() throws {
    let root = repositoryRoot()
    let commands = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookMenuCommands.swift"),
      encoding: .utf8
    )
    for token in [
      "Run Cell and Advance", "Run Cell and Insert Below", "Run All", "Interrupt",
      "Save Notebook", "Save Notebook As", "Move Cell Up", "Move Cell Down",
      "Delete Selected Cell", "Focus Selected Cell Editor", "Leave Cell Editor",
    ] {
      #expect(commands.contains(token), "Missing menu command: \(token)")
    }
  }

  @Test("Native save and close controls expose the required recovery choices")
  func nativeSaveLifecycle() throws {
    let root = repositoryRoot()
    let commands = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookMenuCommands.swift"),
      encoding: .utf8
    )
    let lifecycle = try String(
      contentsOf: root.appending(
        path: "MarimoNative/UI/Notebook/NotebookWindowLifecycleView.swift"
      ),
      encoding: .utf8
    )
    let rootView = notebookSource(root)
    #expect(commands.contains("NotebookSaveActions.save(store)"))
    #expect(commands.contains("NotebookSaveActions.saveAs(store)"))
    for token in ["Save changes before closing?", "Don't Save", "Cancel"] {
      #expect(lifecycle.contains(token))
    }
    for token in ["Reload from Disk", "Save Local Copy", "Cancel"] {
      #expect(rootView.contains(token))
    }
    #expect(!rootView.contains("Auto Save"))
    #expect(!rootView.contains("Merge"))
  }

  @Test("Environment selection and trust remain explicit native gates")
  func nativeEnvironmentAndTrustGate() throws {
    let root = repositoryRoot()
    let preflight = try String(
      contentsOf: root.appending(path: "MarimoNative/Environment/PythonPreflightService.swift"),
      encoding: .utf8
    )
    let trustSheet = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/ExecutionTrustSheet.swift"),
      encoding: .utf8
    )
    let rootView = notebookSource(root)
    let store = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/NotebookEnvironment.swift"),
      encoding: .utf8
    )
    #expect(preflight.contains("arguments: [\"-I\", \"-c\", Self.fixedScript]"))
    #expect(!preflight.contains("/bin/sh"))
    #expect(!preflight.contains("pip install"))
    for token in ["Run Once", "Trust This Folder", "Cancel", "arbitrary Python code"] {
      #expect(trustSheet.contains(token), "Missing trust warning token: \(token)")
    }
    for token in ["Executable", "Python", "Architecture", "marimo", "Environment"] {
      #expect(rootView.contains(token), "Missing environment UI field: \(token)")
    }
    #expect(store.contains("public var interactiveWidgetsAllowed"))
    #expect(store.contains("runOnceAuthorized || executionFolderTrusted"))
    #expect(store.contains("environmentState = .selected("))
  }

  @Test("Secure stdin uses native ephemeral input")
  func secureStdinIsNativeAndEphemeral() throws {
    let root = repositoryRoot()
    let cell = try String(
      contentsOf: root.appending(path: "MarimoNative/UI/Cell/CellView.swift"),
      encoding: .utf8
    )
    let recovery = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/NotebookRecovery.swift"),
      encoding: .utf8
    )
    #expect(cell.contains("SecureField("))
    #expect(cell.contains("stdinText = \"\""))
    #expect(cell.contains(".disabled(prompt.submitted)"))
    #expect(!recovery.contains("Logger("))
    #expect(!recovery.contains("UserDefaults"))
  }

  @Test("Stopped backend recovery exposes logs and manual restart actions")
  func backendRecoveryActionsAreVisible() throws {
    let rootView = notebookSource(repositoryRoot())
    for token in [
      "Backend restart limit reached", "Open Logs", "Restart Backend", "Force Restart Kernel",
    ] {
      #expect(rootView.contains(token), "Missing backend recovery action: \(token)")
    }
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func notebookSource(_ root: URL) -> String {
    (try? String(
      contentsOf: root.appending(path: "MarimoNative/UI/Notebook/NotebookRootView.swift"),
      encoding: .utf8
    )) ?? ""
  }

  private func swiftFiles(below root: URL) throws -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return enumerator.compactMap { item in
      guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
      return url
    }
  }
}
