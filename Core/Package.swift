// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthAnalysisCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HealthAnalysisCore", targets: ["HealthAnalysisCore"]),
    ],
    targets: [
        .target(name: "HealthAnalysisCore"),
        .testTarget(
            name: "HealthAnalysisCoreTests",
            dependencies: ["HealthAnalysisCore"]
        ),
    ]
)
