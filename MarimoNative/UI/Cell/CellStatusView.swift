import SwiftUI

extension CellView {
  @ViewBuilder
  var cellStatus: some View {
    if cell.runtime.stale {
      Image(systemName: "clock.arrow.circlepath")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Stale")
        .accessibilityValue("Cell output is stale")
    } else {
      switch cell.runtime.status {
      case .idle:
        EmptyView()
      case .queued:
        Image(systemName: "clock")
          .font(.caption)
          .accessibilityLabel("Queued")
          .accessibilityValue("Waiting to run")
      case .running:
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Running")
          .accessibilityValue("Cell is running")
      case .error:
        EmptyView()
      case .disabledTransitively:
        Image(systemName: "nosign")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Disabled")
          .accessibilityValue("Cell is disabled by a dependency")
      }
    }
  }
}
