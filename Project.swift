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
            "DEVELOPMENT_TEAM": "2F7QR8NL2D",
            "CODE_SIGN_STYLE": "Automatic",
            // Shared by app and widget extension — the store requires both to match.
            // Bump the build number whenever the widget changes: iOS caches widget
            // gallery previews per bundle version and won't re-render otherwise.
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "2",
            // FoundationModels exists from iOS 26; weak-link so iOS 17–25 still launch.
            "OTHER_LDFLAGS": ["$(inherited)", "-weak_framework", "FoundationModels"],
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
                // utterclip://record — the widget and control open the app into a recording.
                "CFBundleURLTypes": [
                    ["CFBundleURLName": "com.ralfchille.voicer", "CFBundleURLSchemes": ["utterclip"]],
                ],
            ]),
            sources: ["Utterclip/**/*.swift"],
            resources: ["Utterclip/Resources/**"],
            dependencies: [
                .package(product: "WhisperKit"),
                .package(product: "HighlightedTextEditor"),
                .target(name: "UtterclipWidgets"),
            ],
            // Only the app has an icon; the widget extension's catalog holds just the mark.
            settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
        ),
        // Home Screen / Lock Screen widget and the Control Center "Dictate" button.
        // Controls need iOS 18, hence the higher deployment target than the app.
        .target(
            name: "UtterclipWidgets",
            destinations: [.iPhone],
            product: .appExtension,
            bundleId: "com.ralfchille.voicer.widgets",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Utterclip",
                "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
            ]),
            sources: ["UtterclipWidgets/**/*.swift"],
            resources: ["UtterclipWidgets/Resources/**"]
        ),
    ]
)
