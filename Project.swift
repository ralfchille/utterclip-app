import ProjectDescription

let project = Project(
    name: "Utterclip",
    packages: [
        .remote(
            url: "https://github.com/argmaxinc/WhisperKit",
            requirement: .upToNextMajor(from: "0.9.0")
        ),
        .remote(
            url: "https://github.com/kyle-n/HighlightedTextEditor",
            requirement: .upToNextMajor(from: "2.1.2")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.10",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "TARGETED_DEVICE_FAMILY": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "DEVELOPMENT_TEAM": "2F7QR8NL2D",
            "CODE_SIGN_STYLE": "Automatic",
        ]
    ),
    targets: [
        .target(
            name: "Utterclip",
            destinations: [.iPhone],
            product: .app,
            // Kept from the Voicer days on purpose: same app on device, so history and
            // the stored API key carry over across the rename.
            bundleId: "com.ralfchille.voicer",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Utterclip",
                "NSMicrophoneUsageDescription": "Used to record your voice for transcription.",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "ITSAppUsesNonExemptEncryption": false,
            ]),
            sources: ["Utterclip/**/*.swift"],
            resources: ["Utterclip/Resources/**"],
            dependencies: [
                .package(product: "WhisperKit"),
                .package(product: "HighlightedTextEditor")
            ]
        )
    ]
)
