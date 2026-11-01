// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyToDo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TodoDomain", targets: ["TodoDomain"]),
        .library(name: "TodoPersistence", targets: ["TodoPersistence"]),
        .library(name: "TodoInteraction", targets: ["TodoInteraction"]),
        .library(name: "TodoServices", targets: ["TodoServices"]),
        .executable(name: "DailyToDo", targets: ["DailyToDo"]),
        .executable(name: "TodoBenchmark", targets: ["TodoBenchmark"])
    ],
    targets: [
        .target(name: "TodoDomain", exclude: ["README.md"]),
        .target(name: "TodoPersistence", dependencies: ["TodoDomain"], exclude: ["README.md"]),
        .target(name: "TodoInteraction", exclude: ["README.md"]),
        .target(name: "TodoServices", dependencies: ["TodoDomain", "TodoPersistence"], exclude: ["README.md"]),
        .executableTarget(name: "TodoBenchmark", dependencies: ["TodoDomain", "TodoPersistence"], path: "Tools/Benchmark", exclude: ["README.md"]),
        .executableTarget(name: "DailyToDo", dependencies: ["TodoDomain", "TodoPersistence", "TodoInteraction", "TodoServices"], exclude: ["README.md", "App/README.md", "Features/README.md", "Services/README.md"]),
        .testTarget(name: "TodoDomainTests", dependencies: ["TodoDomain"]),
        .testTarget(name: "TodoPersistenceTests", dependencies: ["TodoPersistence", "TodoDomain"]),
        .testTarget(name: "TodoInteractionTests", dependencies: ["TodoInteraction"]),
        .testTarget(name: "TodoServicesTests", dependencies: ["TodoServices", "TodoDomain", "TodoPersistence"]),
        .testTarget(name: "DailyToDoTests", dependencies: ["DailyToDo", "TodoServices", "TodoDomain", "TodoPersistence"], exclude: ["README.md"])
    ]
)
