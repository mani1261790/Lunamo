import AppKit
import MarimoDomain
import MarimoOutput
import SwiftUI

public struct OutputView: View {
  private let output: MarimoOutput
  private let stale: Bool
  private let running: Bool
  @State private var prepared: PreparedOutput?

  public init(output: MarimoOutput, stale: Bool = false, running: Bool = false) {
    self.output = output
    self.stale = stale
    self.running = running
  }

  public var body: some View {
    Group {
      if let prepared {
        preparedView(prepared)
      } else {
        ProgressView("Preparing output…")
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .opacity(stale ? 0.62 : 1)
    .overlay(alignment: .topTrailing) {
      if running {
        Label("Running", systemImage: "progress.indicator")
          .font(.caption)
          .padding(6)
          .background(.background.opacity(0.9), in: Capsule())
          .accessibilityValue("Previous output remains visible while the cell is running")
      } else if stale {
        Label("Stale", systemImage: "clock.arrow.circlepath")
          .font(.caption)
          .padding(6)
          .background(.background.opacity(0.9), in: Capsule())
          .accessibilityValue("Cell output is stale")
      }
    }
    .task(id: preparationID) {
      prepared = nil
      let result = await OutputPreparationService.shared.prepare(output)
      guard !Task.isCancelled else { return }
      prepared = result
    }
  }

  @ViewBuilder
  private func preparedView(_ value: PreparedOutput) -> some View {
    switch value {
    case .text(let text, let masked):
      Text(masked ? String(repeating: "•", count: min(text.count, 64)) : text)
        .font(.body.monospaced())
        .textSelection(.enabled)
        .accessibilityLabel(masked ? "Masked output" : "Text output")
    case .json(let root):
      JSONOutlineView(node: root, initiallyExpanded: true)
        .accessibilityLabel("JSON output")
    case .errors(let errors):
      VStack(alignment: .leading, spacing: 8) {
        ForEach(errors) { error in
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(error.kind).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(error.message).textSelection(.enabled)
              if let line = error.line { Text("Line \(line)").font(.caption) }
            }
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
          }
        }
      }
      .accessibilityLabel("Execution errors")
    case .traceback(let lines):
      VStack(alignment: .leading, spacing: 2) {
        ForEach(lines) { line in
          if let url = line.fileURL {
            HStack(alignment: .firstTextBaseline) {
              Text(line.text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
              Link(destination: url) {
                Image(systemName: "arrow.up.forward.square")
              }
              .accessibilityLabel("Open traceback source")
            }
            .help(line.line.map { "Open \(url.path), line \($0)" } ?? "Open \(url.path)")
          } else {
            Text(line.text).font(.body.monospaced()).textSelection(.enabled)
          }
        }
      }
      .accessibilityLabel("Python traceback")
    case .image(let decoded):
      Image(decorative: decoded.image, scale: 1, orientation: .up)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: CGFloat(decoded.pixelWidth), maxHeight: CGFloat(decoded.pixelHeight))
        .accessibilityLabel("Image output, \(decoded.pixelWidth) by \(decoded.pixelHeight) pixels")
    case .csv(let table):
      CSVTableView(table: table)
        .frame(height: min(360, max(80, CGFloat(table.rows.count + 1) * 24)))
        .accessibilityLabel("CSV table output")
    case .unsupported(let mimeType, let size, let raw):
      recoveryView(
        title: "Unsupported output",
        detail:
          "\(mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))",
        raw: raw
      )
    case .failure(let mimeType, let message, let size, let raw):
      recoveryView(
        title: "Output could not be rendered",
        detail:
          "\(mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))\n\(message)",
        raw: raw
      )
    }
  }

  private func recoveryView(title: String, detail: String, raw: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: "doc.questionmark")
        .font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      HStack {
        Button("Copy Raw Data", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(raw, forType: .string)
        }
        Button("Save Raw Data…", systemImage: "square.and.arrow.down") {
          save(raw)
        }
      }
    }
  }

  private var preparationID: String {
    "\(output.mimeType)|\(output.timestamp ?? 0)|\(output.estimatedByteCount)"
  }

  private func save(_ raw: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "output.txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? Data(raw.utf8).write(to: url, options: .atomic)
  }
}

private struct JSONOutlineView: View {
  let node: JSONOutlineNode
  let initiallyExpanded: Bool
  @State private var expanded: Bool

  init(node: JSONOutlineNode, initiallyExpanded: Bool = false) {
    self.node = node
    self.initiallyExpanded = initiallyExpanded
    _expanded = State(initialValue: initiallyExpanded)
  }

  var body: some View {
    if node.children.isEmpty {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(node.label).font(.body.monospaced()).foregroundStyle(.secondary)
        Text(node.value ?? "").font(.body.monospaced()).textSelection(.enabled)
      }
    } else {
      DisclosureGroup(isExpanded: $expanded) {
        LazyVStack(alignment: .leading, spacing: 3) {
          ForEach(node.children) { child in
            JSONOutlineView(node: child).padding(.leading, 12)
          }
        }
      } label: {
        Text("\(node.label) \(node.value ?? "")").font(.body.monospaced())
      }
    }
  }
}
