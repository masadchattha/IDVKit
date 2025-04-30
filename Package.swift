// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VerifID",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        // Umbrella — re-exports every module, so `import VerifID` gives you the
        // drop-in `VIDVerificationFlowView` and all components in one import.
        .library(name: "VerifID", targets: ["VerifID"]),
        // À-la-carte headless products.
        .library(name: "VerifIDCore", targets: ["VerifIDCore"]),
        .library(name: "VerifIDJPEG2000", targets: ["VerifIDJPEG2000"]),
        .library(name: "VerifIDMRZ", targets: ["VerifIDMRZ"]),
        .library(name: "VerifIDNFC", targets: ["VerifIDNFC"]),
        .library(name: "VerifIDFace", targets: ["VerifIDFace"]),
        // Drop-in customizable UI flow.
        .library(name: "VerifIDUI", targets: ["VerifIDUI"]),
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
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        // PACE needs elliptic-curve point math over brainpool curves, which
        // Apple's crypto stack cannot do. BigInt (pure Swift, MIT, no C) backs a
        // small curve-agnostic implementation covering brainpool + NIST + MODP-DH.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
    ],
    targets: [
        .target(name: "VerifIDCore"),

        // OpenJPEG 2.5.4, vendored as C source (BSD-2-Clause, see LICENSE inside).
        // Compiling from source gives us device + simulator + Catalyst slices,
        // unlike a prebuilt static library.
        .target(
            name: "COpenJPEG",
            exclude: ["LICENSE"],
            publicHeadersPath: "include",
            cSettings: [
                .define("MUTEX_pthread"),
                .define("NDEBUG"),
            ]
        ),

        .target(name: "VerifIDJPEG2000", dependencies: ["VerifIDCore", "COpenJPEG"]),
        .target(
            name: "VerifIDMRZ",
            dependencies: ["VerifIDCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "VerifIDNFC",
            dependencies: [
                "VerifIDCore", "VerifIDMRZ", "VerifIDJPEG2000", "COpenJPEG",
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "VerifIDFace",
            dependencies: ["VerifIDCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "VerifIDUI",
            dependencies: ["VerifIDCore", "VerifIDMRZ", "VerifIDNFC", "VerifIDFace"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "VerifID",
            dependencies: ["VerifIDCore", "VerifIDMRZ", "VerifIDNFC", "VerifIDFace", "VerifIDUI"]
        ),

        .testTarget(name: "VerifIDCoreTests", dependencies: ["VerifIDCore"]),
        .testTarget(name: "VerifIDMRZTests", dependencies: ["VerifIDMRZ"]),
        .testTarget(name: "VerifIDNFCTests", dependencies: ["VerifIDNFC"]),
        .testTarget(name: "VerifIDFaceTests", dependencies: ["VerifIDFace"]),
        .testTarget(
            name: "VerifIDJPEG2000Tests",
            dependencies: ["VerifIDJPEG2000", "COpenJPEG"],
            resources: [.copy("Fixtures/face_64x64.jp2")]
        ),
    ]
)
