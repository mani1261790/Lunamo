import Darwin
import Foundation
import SwiftTerm

// Isolated adoption probe. It never touches notebook files or shell startup files.
final class Capture: LocalProcessDelegate, @unchecked Sendable {
  let lock = NSLock()
  private var bytes = Data()
  private var exited = false
  func dataReceived(slice: ArraySlice<UInt8>) { lock.withLock { bytes.append(contentsOf: slice) } }
  func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
    lock.withLock { exited = true }
  }
  func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
  var text: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }
  var didExit: Bool { lock.withLock { exited } }
  func reset() { lock.withLock { bytes.removeAll() } }
}

func waitUntil(seconds: Double = 5, _ predicate: () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline {
    if predicate() { return true }
    Thread.sleep(forTimeInterval: 0.02)
  }
  return predicate()
}

func send(_ process: LocalProcess, _ text: String) { process.send(data: Array(text.utf8)[...]) }
func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func alive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let python = CommandLine.arguments.dropFirst().first ?? root.appending(path: ".build/Sidecar/bin/python3").path
let capture = Capture()
let process = LocalProcess(delegate: capture)
var environment = ProcessInfo.processInfo.environment
// Non-login, no user startup files: preserve the selected Python PATH exactly.
environment["PATH"] = URL(fileURLWithPath: python).deletingLastPathComponent().path + ":/usr/bin:/bin"
environment["TERM"] = "xterm-256color"
environment["LANG"] = "en_US.UTF-8"
environment["PS1"] = "LUNAMO> "
process.startProcess(executable: "/bin/zsh", args: ["-f", "-i"],
  environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: root.path)
let shellPID = process.shellPid
var results: [String: Bool] = [:]
results["shellStarted"] = waitUntil { capture.text.contains("LUNAMO>") }
send(process, "stty -echo\r")
Thread.sleep(forTimeInterval: 0.1)
capture.reset()
send(process, "python3 -c 'import sys,os; print(\"PYTHON=\"+sys.executable); print(\"TTY=\"+str(sys.stdin.isatty())); print(\"CWD=\"+os.getcwd())'\r")
results["selectedPython"] = waitUntil { capture.text.contains("PYTHON=" + python) }
results["isTTY"] = capture.text.contains("TTY=True")
results["workingDirectory"] = capture.text.contains("CWD=" + root.path)

capture.reset()
send(process, "python3 -q\r")
results["interactivePrompt"] = waitUntil { capture.text.contains(">>>") }
send(process, "print(input('NAME?'))\r")
results["inputPrompt"] = waitUntil { capture.text.contains("NAME?") }
send(process, "日本語の確認\r")
results["japaneseRoundTrip"] = waitUntil { capture.text.contains("日本語の確認") }
send(process, "import time; time.sleep(60)\r")
Thread.sleep(forTimeInterval: 0.15)
send(process, "\u{3}")
results["controlC"] = waitUntil { capture.text.contains("KeyboardInterrupt") }
send(process, "exit()\r")
_ = waitUntil { capture.text.contains("LUNAMO>") }

var size = winsize(ws_row: 33, ws_col: 101, ws_xpixel: 0, ws_ypixel: 0)
_ = process.updateWindowSize(&size)
capture.reset()
send(process, "stty size\r")
results["resize"] = waitUntil { capture.text.contains("33 101") }

// A real foreground child must not survive closing the embedded terminal.
capture.reset()
send(process, "python3 -c 'import os,time; print(\"CHILD=\"+str(os.getpid()),flush=True); time.sleep(60)'\r")
_ = waitUntil { capture.text.contains("CHILD=") }
let childLine = capture.text.components(separatedBy: .newlines).first { $0.hasPrefix("CHILD=") }
let childPID = Int32(childLine?.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
process.terminate()
results["terminateReapsShell"] = waitUntil(seconds: 2) { capture.didExit && !alive(shellPID) }
results["terminateReapsForegroundChild"] = childPID > 0 && !alive(childPID)
// Probe cleanup is restricted to the exact processes it created.
if alive(childPID) { _ = kill(childPID, SIGKILL) }
if alive(shellPID) { _ = kill(shellPID, SIGKILL) }
results["probeCleanup"] = waitUntil { !alive(shellPID) && !alive(childPID) }
let report: [String: Any] = ["swiftTerm": "1.99.3", "python": python, "results": results]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
