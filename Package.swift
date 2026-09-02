// swift-tools-version: 6.2

import PackageDescription

let strictConcurrency: [SwiftSetting] = [
  .unsafeFlags(["-strict-concurrency=complete"])
]

let package = Package(
  name: "MarimoNative",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "MarimoNative", targets: ["MarimoNativeApp"])
  ],
  targets: [
    .target(
      name: "MarimoDomain",
      path: "MarimoNative/Domain",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoProtocol",
      dependencies: ["MarimoDomain"],
      path: "MarimoNative/Protocol",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoProcess",
      path: "MarimoNative/Process",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoDocument",
      dependencies: ["MarimoDomain"],
      path: "MarimoNative/Document",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoBackend",
      dependencies: ["MarimoDomain", "MarimoProtocol", "MarimoProcess"],
      path: "MarimoNative/Backend",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoApplication",
      dependencies: ["MarimoBackend", "MarimoDocument", "MarimoDomain"],
      path: "MarimoNative/Application",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoUI",
      dependencies: ["MarimoApplication", "MarimoDomain"],
      path: "MarimoNative/UI",
      swiftSettings: strictConcurrency
    ),
    .executableTarget(
      name: "MarimoNativeApp",
      dependencies: ["MarimoApplication", "MarimoBackend", "MarimoUI"],
      path: "MarimoNative/App",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "MarimoNativeTests",
      dependencies: [
        "MarimoApplication", "MarimoBackend", "MarimoDomain", "MarimoProcess", "MarimoProtocol",
      ],
      path: "Tests/Unit",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "MarimoContractTests",
      dependencies: ["MarimoDomain", "MarimoProtocol"],
      path: "Tests/Contract",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "MarimoIntegrationTests",
      dependencies: ["MarimoBackend", "MarimoDomain", "MarimoProcess", "MarimoProtocol"],
      path: "Tests/Integration",
      swiftSettings: strictConcurrency
    ),
  ],
  swiftLanguageModes: [.v6]
)
