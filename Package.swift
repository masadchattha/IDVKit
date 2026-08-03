// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IDVKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        // Umbrella — re-exports every module, so `import IDVKit` gives you the
        // drop-in `IDVVerificationFlowView` and all components in one import.
        .library(name: "IDVKit", targets: ["IDVKit"]),
        // À-la-carte headless products.
        .library(name: "IDVKitCore", targets: ["IDVKitCore"]),
        .library(name: "IDVKitJPEG2000", targets: ["IDVKitJPEG2000"]),
        .library(name: "IDVKitMRZ", targets: ["IDVKitMRZ"]),
        .library(name: "IDVKitNFC", targets: ["IDVKitNFC"]),
        .library(name: "IDVKitFace", targets: ["IDVKitFace"]),
        // Drop-in customizable UI flow.
        .library(name: "IDVKitUI", targets: ["IDVKitUI"])
    ],
    dependencies: [
        // Passport passive authentication: hand-parse the SOD's CMS with
        // SwiftASN1 and verify the DSC/chain with X509. Both pure-Swift, no
        // networking; X509 pulls swift-crypto (Crypto, _CryptoExtras) too.
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.19.3"),
        // swift-crypto (already transitive via swift-certificates) — declared
        // directly for CryptoKit's `Crypto` and `_CryptoExtras` (AES-CMAC,
        // AES-CBC) used by PACE's AES Secure Messaging.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        // PACE needs elliptic-curve point math over brainpool curves, which
        // Apple's crypto stack cannot do. BigInt (pure Swift, MIT, no C) backs a
        // small curve-agnostic implementation covering brainpool + NIST + MODP-DH.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0")
    ],
    targets: [
        .target(name: "IDVKitCore", resources: [.copy("PrivacyInfo.xcprivacy")]),

        // OpenJPEG 2.5.4, vendored as C source (BSD-2-Clause, see LICENSE inside).
        // Compiling from source gives us device + simulator + Catalyst slices,
        // unlike a prebuilt static library.
        .target(
            name: "COpenJPEG",
            exclude: ["LICENSE"],
            publicHeadersPath: "include",
            cSettings: [
                .define("MUTEX_pthread"),
                .define("NDEBUG")
            ]
        ),

        .target(
            name: "IDVKitJPEG2000",
            dependencies: ["IDVKitCore", "COpenJPEG"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVKitMRZ",
            dependencies: ["IDVKitCore"],
            resources: [.process("Resources"), .copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVKitNFC",
            dependencies: [
                "IDVKitCore", "IDVKitMRZ", "IDVKitJPEG2000", "COpenJPEG",
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto")
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVKitFace",
            dependencies: ["IDVKitCore"],
            resources: [.process("Resources"), .copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVKitUI",
            dependencies: ["IDVKitCore", "IDVKitMRZ", "IDVKitNFC", "IDVKitFace"],
            resources: [.process("Resources"), .copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVKit",
            dependencies: ["IDVKitCore", "IDVKitMRZ", "IDVKitNFC", "IDVKitFace", "IDVKitUI"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),

        .testTarget(name: "IDVKitCoreTests", dependencies: ["IDVKitCore"]),
        .testTarget(name: "IDVKitMRZTests", dependencies: ["IDVKitMRZ"]),
        .testTarget(name: "IDVKitNFCTests", dependencies: ["IDVKitNFC"]),
        .testTarget(name: "IDVKitFaceTests", dependencies: ["IDVKitFace"]),
        .testTarget(
            name: "IDVKitJPEG2000Tests",
            dependencies: ["IDVKitJPEG2000", "COpenJPEG"],
            resources: [.copy("Fixtures/face_64x64.jp2")]
        )
    ]
)
