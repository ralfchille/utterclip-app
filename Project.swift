import ProjectDescription

let project = Project(
    name: "Voicer",
    packages: [
        .remote(
            url: "https://github.com/argmaxinc/WhisperKit",
            requirement: .upToNextMajor(from: "0.9.0")
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
            name: "Voicer",
            destinations: [.iPhone],
            product: .app,
            bundleId: "com.babbellabs.voicer",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Voicer",
                "NSMicrophoneUsageDescription": "Used to record your voice for transcription.",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "ITSAppUsesNonExemptEncryption": false,
            ]),
            sources: ["Voicer/**/*.swift"],
            resources: ["Voicer/Resources/**"],
            dependencies: [
                .package(product: "WhisperKit")
            ]
        )
    ]
)
