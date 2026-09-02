import AppKit
import MarimoOutput
import SwiftUI

struct CSVTableView: NSViewRepresentable {
  let table: CSVTable

  func makeCoordinator() -> Coordinator { Coordinator(table: table) }

  func makeNSView(context: Context) -> NSScrollView {
    let tableView = NSTableView()
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.rowSizeStyle = .small
    tableView.delegate = context.coordinator
    tableView.dataSource = context.coordinator
    configureColumns(tableView)

    let scroll = NSScrollView()
    scroll.documentView = tableView
    scroll.hasHorizontalScroller = true
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.table = table
    guard let tableView = scroll.documentView as? NSTableView else { return }
    if tableView.tableColumns.count != table.columns.count { configureColumns(tableView) }
    tableView.reloadData()
  }

  private func configureColumns(_ tableView: NSTableView) {
    for column in tableView.tableColumns { tableView.removeTableColumn(column) }
    for (index, name) in table.columns.enumerated() {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
      column.title = name.isEmpty ? "Column \(index + 1)" : name
      column.minWidth = 80
      column.width = 140
      tableView.addTableColumn(column)
    }
  }

  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var table: CSVTable

    init(table: CSVTable) { self.table = table }

    func numberOfRows(in _: NSTableView) -> Int { table.rows.count }

    func tableView(
      _ tableView: NSTableView,
      viewFor tableColumn: NSTableColumn?,
      row: Int
    ) -> NSView? {
      guard let tableColumn,
        let column = Int(tableColumn.identifier.rawValue),
        table.rows.indices.contains(row)
      else { return nil }
      let identifier = NSUserInterfaceItemIdentifier("CSVCell")
      let field =
        tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
        ?? NSTextField(labelWithString: "")
      field.identifier = identifier
      field.lineBreakMode = .byTruncatingTail
      field.stringValue = table.rows[row].indices.contains(column) ? table.rows[row][column] : ""
      field.toolTip = field.stringValue
      return field
    }
  }
}
