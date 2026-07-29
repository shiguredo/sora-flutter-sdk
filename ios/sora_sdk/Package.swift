// swift-tools-version: 5.9

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let exportedSymbolsPath = "\(packageRoot)/exported_symbols.exp"
let libwebrtcCXCFrameworkURL =
  "https://github.com/shiguredo/webrtc-rs/releases/download/0.150.0/libwebrtc_c.xcframework.zip"
let libwebrtcCXCFrameworkChecksum =
  "28fe87e5368bde34acacd4dc409f3b98d9bd60898ae37af2e8dda009787dc7cf"

let package = Package(
  name: "sora_sdk",
  platforms: [
    .iOS("16.0")
  ],
  products: [
    .library(name: "sora-sdk", targets: ["sora_sdk"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .binaryTarget(
      name: "webrtc_c",
      url: libwebrtcCXCFrameworkURL,
      checksum: libwebrtcCXCFrameworkChecksum
    ),
    .target(
      name: "CWebrtc",
      dependencies: [
        "webrtc_c"
      ],
      path: "Sources/CWebrtc",
      publicHeadersPath: "CWebrtc",
      cSettings: [
        .define("WEBRTC_MAC", to: "1"),
        .define("WEBRTC_IOS", to: "1"),
        .define("WEBRTC_POSIX", to: "1"),
        .define("OPENSSL_IS_BORINGSSL", to: "1"),
        .define("NDEBUG"),
      ]
    ),
    .target(
      name: "sora_sdk",
      dependencies: [
        "CWebrtc",
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      path: "Sources/sora_sdk",
      linkerSettings: [
        .linkedLibrary("c++"),
        .linkedLibrary("c++abi"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreMedia"),
        .linkedFramework("CoreVideo"),
        .linkedFramework("GLKit"),
        .linkedFramework("IOSurface"),
        .linkedFramework("Metal"),
        .linkedFramework("MetalKit"),
        .linkedFramework("Network"),
        .linkedFramework("QuartzCore"),
        .linkedFramework("Security"),
        .linkedFramework("VideoToolbox"),
        // -all_load: SPM の binaryTarget では特定アーカイブへの -force_load が
        // 指定できないため全静的ライブラリを強制ロードする。
        // sora_sdk の依存は webrtc_c と FlutterFramework のみであり、
        // 不要なアーカイブが追加で force-load されることはない。
        .unsafeFlags([
          "-ObjC",
          "-all_load",
          "-Xlinker", "-exported_symbols_list",
          "-Xlinker", exportedSymbolsPath,
        ]),
      ]
    ),
  ]
)
