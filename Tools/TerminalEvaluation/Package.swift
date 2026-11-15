// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "TerminalEvaluation",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3")
  ],
  targets: [
    .executableTarget(
      name: "TerminalEvaluation",
      dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]
    )
  ]
)
