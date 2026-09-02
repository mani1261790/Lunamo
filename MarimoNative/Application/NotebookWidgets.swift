import MarimoDomain
import MarimoWidgets

extension NotebookStore {
  public func submitWidgetValue(
    objectID: String,
    value: Double,
    expectedSessionID: String
  ) async {
    guard interactiveWidgetsAllowed,
      let currentSessionID = document.kernelSessionID,
      currentSessionID == expectedSessionID,
      value.isFinite
    else { return }
    do {
      try await backend.updateUIElement(
        notebookURI: document.notebookURI,
        kernelSessionID: currentSessionID,
        objectIDs: [objectID],
        values: [.number(value)]
      )
      MarimoLog.widget.debug("Sent widget update count=1")
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  func sliderDescriptors(from output: MarimoOutput?) -> [MarimoSliderDescriptor] {
    guard let output else { return [] }
    if output.mimeType.lowercased() == "text/html", case .string(let source) = output.data,
      let descriptor = MarimoComponentDecoder.slider(from: source)
    {
      return [descriptor]
    }
    if output.mimeType.lowercased() == "application/vnd.marimo+mimebundle",
      case .object(let bundle) = output.data,
      case .string(let source)? = bundle["text/html"],
      let descriptor = MarimoComponentDecoder.slider(from: source)
    {
      return [descriptor]
    }
    return []
  }
}
