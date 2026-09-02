import Foundation
import SwiftSoup

public enum SliderOrientation: String, Sendable, Equatable {
  case horizontal
  case vertical
}

public struct MarimoSliderDescriptor: Sendable, Equatable {
  public let objectID: String
  public let randomID: String
  public let initialValue: Double
  public let labelHTML: String?
  public let start: Double
  public let stop: Double
  public let step: Double?
  public let steps: [Double]?
  public let debounce: Bool
  public let orientation: SliderOrientation
  public let showValue: Bool
  public let fullWidth: Bool
  public let includeInput: Bool
  public let disabled: Bool

  public init(
    objectID: String,
    randomID: String,
    initialValue: Double,
    labelHTML: String?,
    start: Double,
    stop: Double,
    step: Double?,
    steps: [Double]?,
    debounce: Bool,
    orientation: SliderOrientation,
    showValue: Bool,
    fullWidth: Bool,
    includeInput: Bool,
    disabled: Bool
  ) {
    self.objectID = objectID
    self.randomID = randomID
    self.initialValue = initialValue
    self.labelHTML = labelHTML
    self.start = start
    self.stop = stop
    self.step = step
    self.steps = steps
    self.debounce = debounce
    self.orientation = orientation
    self.showValue = showValue
    self.fullWidth = fullWidth
    self.includeInput = includeInput
    self.disabled = disabled
  }

  public var positionRange: ClosedRange<Double> {
    if let steps, !steps.isEmpty { return 0...Double(steps.count - 1) }
    return start...stop
  }

  public func normalizedPosition(_ value: Double) -> Double {
    guard value.isFinite else { return initialValue }
    let range = positionRange
    let clamped = min(max(value, range.lowerBound), range.upperBound)
    if let steps, !steps.isEmpty { return clamped.rounded() }
    guard let step else { return clamped }
    let offset = ((clamped - start) / step).rounded() * step
    let stepped = start + offset
    guard stepped.isFinite else { return clamped }
    return min(max(stepped, range.lowerBound), range.upperBound)
  }

  public func displayValue(for position: Double) -> Double {
    guard let steps, !steps.isEmpty else { return normalizedPosition(position) }
    return steps[Int(normalizedPosition(position))]
  }

  public func position(forDisplayValue value: Double) -> Double {
    guard value.isFinite else { return initialValue }
    guard let steps, !steps.isEmpty else { return normalizedPosition(value) }
    let nearest = steps.enumerated().min { left, right in
      abs(left.element - value) < abs(right.element - value)
    }
    return Double(nearest?.offset ?? 0)
  }
}

public enum MarimoComponentDecoder {
  public static func slider(from source: String) -> MarimoSliderDescriptor? {
    guard !source.isEmpty,
      let document = try? SwiftSoup.parseBodyFragment(source),
      let body = document.body(),
      let outer = soleMeaningfulChild(of: body) as? Element,
      outer.tagNameNormal() == "marimo-ui-element",
      let objectID = nonemptyAttribute("object-id", in: outer),
      let randomID = nonemptyAttribute("random-id", in: outer),
      let slider = soleMeaningfulChild(of: outer) as? Element,
      slider.tagNameNormal() == "marimo-slider",
      meaningfulChildren(of: slider).isEmpty,
      let initialValue = numberAttribute("data-initial-value", in: slider),
      let start = numberAttribute("data-start", in: slider),
      let stop = numberAttribute("data-stop", in: slider),
      let steps = numberArrayAttribute("data-steps", in: slider),
      let debounce = boolAttribute("data-debounce", in: slider),
      let orientationValue = stringAttribute("data-orientation", in: slider),
      let orientation = SliderOrientation(rawValue: orientationValue),
      let showValue = boolAttribute("data-show-value", in: slider),
      let fullWidth = boolAttribute("data-full-width", in: slider),
      let includeInput = boolAttribute("data-include-input", in: slider),
      let disabled = boolAttribute("data-disabled", in: slider)
    else { return nil }

    let step = optionalNumberAttribute("data-step", in: slider)
    let labelHTML = optionalStringAttribute("data-label", in: slider)
    guard initialValue.isFinite, start.isFinite, stop.isFinite, start <= stop,
      step == nil || (step?.isFinite == true && step! > 0),
      steps.allSatisfy(\.isFinite)
    else { return nil }

    if !steps.isEmpty {
      guard initialValue.rounded() == initialValue,
        initialValue >= 0,
        initialValue < Double(steps.count)
      else { return nil }
    } else {
      guard initialValue >= start, initialValue <= stop else { return nil }
    }

    return MarimoSliderDescriptor(
      objectID: objectID,
      randomID: randomID,
      initialValue: initialValue,
      labelHTML: labelHTML,
      start: start,
      stop: stop,
      step: step,
      steps: steps,
      debounce: debounce,
      orientation: orientation,
      showValue: showValue,
      fullWidth: fullWidth,
      includeInput: includeInput,
      disabled: disabled
    )
  }

  public static func plainText(fromHTML source: String?) -> String? {
    guard let source, !source.isEmpty,
      let document = try? SwiftSoup.parseBodyFragment(source),
      let body = document.body(),
      let value = try? body.text().trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else { return nil }
    return value
  }

  private static func soleMeaningfulChild(of node: Node) -> Node? {
    let children = meaningfulChildren(of: node)
    return children.count == 1 ? children[0] : nil
  }

  private static func meaningfulChildren(of node: Node) -> [Node] {
    node.getChildNodes().filter { child in
      if let text = child as? TextNode {
        return !text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      return child is Element
    }
  }

  private static func nonemptyAttribute(_ name: String, in element: Element) -> String? {
    guard element.hasAttr(name), let value = try? element.attr(name), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func decodedAttribute(_ name: String, in element: Element) -> Any? {
    guard element.hasAttr(name), let encoded = try? element.attr(name),
      let data = encoded.data(using: .utf8)
    else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }

  private static func numberAttribute(_ name: String, in element: Element) -> Double? {
    guard let value = decodedAttribute(name, in: element) as? NSNumber,
      CFGetTypeID(value) != CFBooleanGetTypeID()
    else { return nil }
    return value.doubleValue
  }

  private static func optionalNumberAttribute(_ name: String, in element: Element) -> Double? {
    guard element.hasAttr(name) else { return nil }
    return numberAttribute(name, in: element)
  }

  private static func numberArrayAttribute(_ name: String, in element: Element) -> [Double]? {
    guard let values = decodedAttribute(name, in: element) as? [Any] else { return nil }
    var decoded: [Double] = []
    for value in values {
      guard let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID()
      else { return nil }
      decoded.append(number.doubleValue)
    }
    return decoded
  }

  private static func boolAttribute(_ name: String, in element: Element) -> Bool? {
    guard let value = decodedAttribute(name, in: element) as? NSNumber,
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else { return nil }
    return value.boolValue
  }

  private static func stringAttribute(_ name: String, in element: Element) -> String? {
    decodedAttribute(name, in: element) as? String
  }

  private static func optionalStringAttribute(_ name: String, in element: Element) -> String? {
    guard element.hasAttr(name) else { return nil }
    if decodedAttribute(name, in: element) is NSNull { return nil }
    return stringAttribute(name, in: element)
  }
}
