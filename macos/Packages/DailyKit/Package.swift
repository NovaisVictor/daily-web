// swift-tools-version: 6.2
import PackageDescription

// Every target is declared here up front so that parallel work never edits this
// manifest: each feature owns its own Sources/<Target> and Tests/<Target>Tests.
// Changing this file is the orchestrator's job (see macos/AGENTS.md).

let strict: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .treatAllWarnings(as: .error),
]

// UI code runs on the main actor by default; Models and API stay nonisolated
// so decoding and networking never hop to the main thread.
let ui: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let features: [(name: String, extra: [Target.Dependency])] = [
  ("FeatureShell", [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")]),
  ("FeatureHome", []),
  ("FeatureTasks", []),
  ("FeatureNotes", [.product(name: "Textual", package: "textual")]),
  ("FeatureEmail", []),
  ("FeatureAgenda", []),
  ("FeatureJira", []),
  ("FeaturePulls", []),
  ("FeatureSlack", []),
  ("FeatureAgents", []),
  ("FeatureAccess", []),
  ("FeatureNotifications", []),
  ("FeatureSettings", []),
]

let core: [Target] = [
  .target(name: "DailyModels", swiftSettings: strict),
  .target(name: "DailyAPI", dependencies: ["DailyModels"], swiftSettings: strict),
  .target(name: "DailyStorage", dependencies: ["DailyModels", "DailyAPI"], swiftSettings: strict),
  // Geist Sans/Mono (SIL OFL 1.1, license shipped next to the files).
  .target(name: "DailyDesign", resources: [.copy("Resources/Fonts")], swiftSettings: ui),
  .target(
    name: "DailyCore",
    dependencies: ["DailyModels", "DailyAPI", "DailyStorage"],
    swiftSettings: ui
  ),
]

let coreTests: [Target] = [
  .testTarget(
    name: "DailyModelsTests",
    dependencies: ["DailyModels"],
    resources: [.copy("Fixtures")],
    swiftSettings: strict
  ),
  .testTarget(name: "DailyAPITests", dependencies: ["DailyAPI"], swiftSettings: strict),
  .testTarget(name: "DailyStorageTests", dependencies: ["DailyStorage"], swiftSettings: strict),
  .testTarget(name: "DailyDesignTests", dependencies: ["DailyDesign"], swiftSettings: ui),
  .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"], swiftSettings: ui),
]

let featureTargets: [Target] = features.flatMap { feature -> [Target] in
  [
    .target(
      name: feature.name,
      dependencies: ["DailyModels", "DailyAPI", "DailyCore", "DailyDesign"] + feature.extra,
      swiftSettings: ui
    ),
    .testTarget(name: "\(feature.name)Tests", dependencies: [.target(name: feature.name)], swiftSettings: ui),
  ]
}

let package = Package(
  name: "DailyKit",
  defaultLocalization: "pt-BR",
  platforms: [.macOS(.v26)],
  products: [
    .library(
      name: "DailyKit",
      targets: ["DailyModels", "DailyAPI", "DailyStorage", "DailyDesign", "DailyCore"] + features.map(\.name)
    )
  ],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/textual", exact: "0.5.0"),
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
  ],
  targets: core + coreTests + featureTargets
)
