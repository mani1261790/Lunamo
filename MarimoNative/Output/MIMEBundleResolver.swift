import Foundation
import MarimoDomain

public struct MIMEBundleRepresentation: Sendable, Equatable, Identifiable {
  public let mimeType: String
  public let data: JSONValue
  public let metadata: JSONValue?
  public let displaySize: OutputDisplaySize?

  public var id: String { mimeType }

  public init(
    mimeType: String,
    data: JSONValue,
    metadata: JSONValue?,
    displaySize: OutputDisplaySize?
  ) {
    self.mimeType = mimeType
    self.data = data
    self.metadata = metadata
    self.displaySize = displaySize
  }

  public func output(inheriting output: MarimoOutput) -> MarimoOutput {
    MarimoOutput(
      channel: output.channel,
      mimeType: mimeType,
      data: data,
      timestamp: output.timestamp,
      displaySize: displaySize
    )
  }
}

public struct ResolvedMIMEBundle: Sendable, Equatable {
  public let representations: [MIMEBundleRepresentation]
  public let metadata: JSONValue?

  public init(representations: [MIMEBundleRepresentation], metadata: JSONValue?) {
    self.representations = representations
    self.metadata = metadata
  }
}

public enum MIMEBundleResolver {
  public static let mimeType = "application/vnd.marimo+mimebundle"

  public static let precedence = [
    "text/html",
    "application/vnd.vegalite.v6+json",
    "application/vnd.vegalite.v5+json",
    "application/vnd.vega.v6+json",
    "application/vnd.vega.v5+json",
    "image/svg+xml",
    "image/png",
    "image/jpeg",
    "image/gif",
    "text/markdown",
    "text/latex",
    "text/csv",
    "application/json",
    "text/plain",
    "video/mp4",
    "video/mpeg",
  ]

  private static let htmlFallbackImages: Set<String> = [
    "image/png", "image/jpeg", "image/gif", "image/avif", "image/bmp", "image/tiff",
  ]
  private static let vegaFallbackImages: Set<String> = [
    "image/png", "image/jpeg", "image/gif",
  ]
  private static let vegaTypes: Set<String> = [
    "application/vnd.vegalite.v6+json",
    "application/vnd.vegalite.v5+json",
    "application/vnd.vega.v6+json",
    "application/vnd.vega.v5+json",
  ]

  public static func resolve(_ output: MarimoOutput) throws -> ResolvedMIMEBundle {
    guard output.mimeType.lowercased() == mimeType else {
      throw MIMEBundleResolutionError.wrongMIMEType
    }
    let value = try bundleValue(from: output.data)
    guard case .object(let object) = value else {
      throw MIMEBundleResolutionError.expectedObject
    }

    let metadata = object["__metadata__"]
    var metadataByMIME: [String: JSONValue] = [:]
    if case .object(let entries)? = metadata {
      for (key, value) in entries { metadataByMIME[key.lowercased()] = value }
    }

    var dataByMIME: [String: JSONValue] = [:]
    for (key, data) in object where key != "__metadata__" {
      dataByMIME[key.lowercased()] = data
    }
    guard !dataByMIME.isEmpty else { throw MIMEBundleResolutionError.emptyBundle }

    let keys = Set(dataByMIME.keys)
    let hidden: Set<String>
    if keys.contains("text/html") {
      hidden = htmlFallbackImages
    } else if !keys.isDisjoint(with: vegaTypes) {
      hidden = vegaFallbackImages
    } else {
      hidden = []
    }

    let priority = Dictionary(uniqueKeysWithValues: precedence.enumerated().map { ($1, $0) })
    let visible = keys.subtracting(hidden).sorted { left, right in
      let leftPriority = priority[left] ?? Int.max
      let rightPriority = priority[right] ?? Int.max
      return leftPriority == rightPriority ? left < right : leftPriority < rightPriority
    }
    guard !visible.isEmpty else { throw MIMEBundleResolutionError.emptyBundle }

    let representations = visible.compactMap { mime -> MIMEBundleRepresentation? in
      guard let data = dataByMIME[mime] else { return nil }
      let mimeMetadata = metadataByMIME[mime]
      return MIMEBundleRepresentation(
        mimeType: mime,
        data: data,
        metadata: mimeMetadata,
        displaySize: displaySize(from: mimeMetadata)
      )
    }
    return ResolvedMIMEBundle(representations: representations, metadata: metadata)
  }

  private static func bundleValue(from data: JSONValue) throws -> JSONValue {
    if case .string(let source) = data {
      do {
        return try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
      } catch {
        throw MIMEBundleResolutionError.invalidJSON
      }
    }
    return data
  }

  private static func displaySize(from metadata: JSONValue?) -> OutputDisplaySize? {
    guard case .object(let values)? = metadata else { return nil }
    let width = validDimension(values["width"])
    let height = validDimension(values["height"])
    guard width != nil || height != nil else { return nil }
    return OutputDisplaySize(width: width, height: height)
  }

  private static func validDimension(_ value: JSONValue?) -> Double? {
    let number: Double?
    switch value {
    case .integer(let value): number = Double(value)
    case .number(let value): number = value
    default: number = nil
    }
    guard let number, number.isFinite, number > 0, number <= 100_000 else { return nil }
    return number
  }
}

public enum MIMEBundleResolutionError: Error, Sendable, Equatable {
  case wrongMIMEType
  case expectedObject
  case invalidJSON
  case emptyBundle
}
