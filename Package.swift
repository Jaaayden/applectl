// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "applectl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "applectl-native", targets: ["applectl"])],
    targets: [
        .target(name: "RemindCore", linkerSettings: [.linkedFramework("EventKit"), .linkedFramework("CoreLocation")]),
        .target(name: "AppleCore", dependencies: ["RemindCore"], linkerSettings: [.linkedFramework("EventKit")]),
        .executableTarget(name: "applectl", dependencies: ["AppleCore"]),
        .testTarget(name: "AppleCoreTests", dependencies: ["AppleCore", "RemindCore"]),
    ],
    swiftLanguageModes: [.v6]
)
