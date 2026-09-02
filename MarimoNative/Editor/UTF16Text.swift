import Foundation

public struct UTF16Text: Sendable, Equatable {
  public let source: String

  public init(_ source: String) {
    self.source = source
  }

  public var length: Int { (source as NSString).length }

  public func character(at location: Int) -> unichar {
    (source as NSString).character(at: location)
  }

  public func substring(with range: NSRange) -> String {
    (source as NSString).substring(with: range)
  }

  public func replacingCharacters(in range: NSRange, with replacement: String) -> String {
    (source as NSString).replacingCharacters(in: range, with: replacement)
  }

  public func lineRange(for range: NSRange) -> NSRange {
    (source as NSString).lineRange(for: range)
  }
}
