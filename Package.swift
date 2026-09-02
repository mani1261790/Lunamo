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
      name: "MarimoEnvironment",
      dependencies: ["MarimoProcess"],
      path: "MarimoNative/Environment",
      exclude: ["README.md"],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoDocument",
      dependencies: ["MarimoDomain"],
      path: "MarimoNative/Document",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoEditor",
      dependencies: ["MarimoDomain"],
      path: "MarimoNative/Editor",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoOutput",
      dependencies: ["MarimoDomain"],
      path: "MarimoNative/Output",
      exclude: ["README.md"],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoWebFallback",
      dependencies: ["MarimoOutput"],
      path: "MarimoNative/WebFallback",
      exclude: ["README.md"],
      resources: [.copy("Assets")],
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
      dependencies: ["MarimoBackend", "MarimoDocument", "MarimoDomain", "MarimoEnvironment"],
      path: "MarimoNative/Application",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoUI",
      dependencies: [
        "MarimoApplication", "MarimoDomain", "MarimoEditor", "MarimoEnvironment", "MarimoOutput",
        "MarimoWebFallback",
      ],
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
        "MarimoApplication", "MarimoBackend", "MarimoDomain", "MarimoEditor", "MarimoProcess",
        "MarimoProtocol", "MarimoEnvironment", "MarimoOutput", "MarimoWebFallback",
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
      dependencies: [
        "MarimoApplication", "MarimoBackend", "MarimoDomain", "MarimoEnvironment",
        "MarimoOutput", "MarimoProcess", "MarimoProtocol",
      ],
      path: "Tests/Integration",
      swiftSettings: strictConcurrency
    ),
  ],
  swiftLanguageModes: [.v6]
)
