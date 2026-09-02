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

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
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
