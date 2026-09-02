import Foundation
import MarimoProtocol
import Testing

@Suite("JSON-RPC framing")
struct JSONRPCFramingTests {
  private let payload = Data(#"{"jsonrpc":"2.0","id":1,"result":null}"#.utf8)

  @Test("One-byte input boundaries preserve the message")
  func oneByteAtATime() throws {
    let frame = try JSONRPCFramer.frame(payload)
    var framer = JSONRPCFramer()
    var messages: [Data] = []
    for byte in frame {
      messages += try framer.append(Data([byte]))
    }
    #expect(messages == [payload])
  }

  @Test("Every header split is buffered")
  func headerSplitAtEveryByte() throws {
    let frame = try JSONRPCFramer.frame(payload)
    let headerLength = frame.range(of: Data([13, 10, 13, 10]))?.upperBound ?? 0
    for split in 1..<headerLength {
      var framer = JSONRPCFramer()
      #expect(try framer.append(frame.prefix(split)).isEmpty)
      #expect(try framer.append(frame.dropFirst(split)) == [payload])
    }
  }

  @Test("Every payload split is buffered")
  func payloadSplitAtEveryByte() throws {
    let frame = try JSONRPCFramer.frame(payload)
    let headerLength = frame.count - payload.count
    for payloadSplit in 0..<payload.count {
      let split = headerLength + payloadSplit
      var framer = JSONRPCFramer()
      #expect(try framer.append(frame.prefix(split)).isEmpty)
      #expect(try framer.append(frame.dropFirst(split)) == [payload])
    }
  }

  @Test("Multiple concatenated messages are emitted")
  func multipleMessages() throws {
    let frame = try JSONRPCFramer.frame(payload)
    var combined = frame
    combined.append(frame)
    var framer = JSONRPCFramer()
    #expect(try framer.append(combined) == [payload, payload])
  }

  @Test(
    "Invalid lengths close framing",
    arguments: ["-1", "abc", "67108865"]
  )
  func invalidLength(value: String) {
    var framer = JSONRPCFramer()
    let frame = Data("Content-Length: \(value)\r\n\r\n".utf8)
    #expect(throws: JSONRPCFramingError.self) { try framer.append(frame) }
  }

  @Test("Invalid UTF-8 is rejected")
  func invalidUTF8() {
    var framer = JSONRPCFramer()
    var frame = Data("Content-Length: 2\r\n\r\n".utf8)
    frame.append(contentsOf: [0xC3, 0x28])
    #expect(throws: JSONRPCFramingError.invalidUTF8) { try framer.append(frame) }
  }

  @Test("Protocol text outside a frame is rejected")
  func protocolTextOutsideFrame() {
    var framer = JSONRPCFramer()
    #expect(throws: JSONRPCFramingError.protocolTextOutsideFrame) {
      try framer.append(Data("debug output\n".utf8))
    }
  }
}
