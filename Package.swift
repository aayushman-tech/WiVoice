// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "WiVoice",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WiVoice", targets: ["WiVoice"])],
    targets: [.executableTarget(name: "WiVoice", path: "Sources/WiVoice", resources: [.copy("receiver.html")])]
)
