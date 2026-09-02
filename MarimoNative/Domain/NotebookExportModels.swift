public enum NotebookDisplayTheme: String, Sendable, Equatable {
  case light, dark
}

public enum NotebookExportFormat: String, CaseIterable, Sendable, Equatable {
  case html, ipynb, markdown

  public var filenameExtension: String {
    switch self {
    case .html: "html"
    case .ipynb: "ipynb"
    case .markdown: "md"
    }
  }
}
