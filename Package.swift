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
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.5")
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
      dependencies: ["MarimoDomain"],
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
      dependencies: [
        "MarimoDomain", "MarimoWidgets",
        .product(name: "SwiftSoup", package: "SwiftSoup"),
      ],
      path: "MarimoNative/Output",
      exclude: ["README.md"],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoWidgets",
      dependencies: [
        "MarimoDomain",
        .product(name: "SwiftSoup", package: "SwiftSoup"),
      ],
      path: "MarimoNative/Widgets",
      exclude: ["README.md"],
      resources: [.copy("LICENSE-SwiftSoup")],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoWebFallback",
      dependencies: ["MarimoDomain", "MarimoOutput"],
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
      dependencies: [
        "MarimoBackend", "MarimoDocument", "MarimoDomain", "MarimoEnvironment", "MarimoWidgets",
      ],
      path: "MarimoNative/Application",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "MarimoUI",
      dependencies: [
        "MarimoApplication", "MarimoDomain", "MarimoEditor", "MarimoEnvironment", "MarimoOutput",
        "MarimoWebFallback", "MarimoWidgets",
      ],
      path: "MarimoNative/UI",
      swiftSettings: strictConcurrency
    ),
    .executableTarget(
      name: "MarimoNativeApp",
      dependencies: ["MarimoApplication", "MarimoBackend", "MarimoDomain", "MarimoUI"],
      path: "MarimoNative/App",
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "MarimoNativeTests",
      dependencies: [
        "MarimoApplication", "MarimoBackend", "MarimoDomain", "MarimoEditor", "MarimoProcess",
        "MarimoProtocol", "MarimoEnvironment", "MarimoOutput", "MarimoWebFallback",
        "MarimoWidgets",
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
