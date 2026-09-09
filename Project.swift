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
            // Shared by app, core framework and widget extension — the store requires
            // them to match. Bump the build number whenever the widget changes: iOS caches
            // widget gallery previews per bundle version and won't re-render otherwise.
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "3",
            // FoundationModels exists from iOS 26 / macOS 26; weak-link so older systems
            // still launch.
            "OTHER_LDFLAGS": ["$(inherited)", "-weak_framework", "FoundationModels"],
        ]
    ),
    targets: [
        // Everything below the UI — recording, transcription, rewriting, redaction, the
        // stores and the view model — so a macOS app can share it with the iPhone app.
        // Builds for both platforms; the few platform differences are `#if`-guarded inside.
        .target(
            name: "UtterclipCore",
            destinations: [.iPhone, .mac],
            product: .framework,
            bundleId: "com.ralfchille.voicer.core",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .default,
            sources: ["UtterclipCore/**/*.swift"],
            // Privacy manifest: the stores use UserDefaults (required-reason API CA92.1).
            resources: ["UtterclipCore/Resources/**"],
            dependencies: [
                .package(product: "WhisperKit"),
            ]
        ),
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
                .target(name: "UtterclipCore"),
                .package(product: "HighlightedTextEditor"),
                .target(name: "UtterclipWidgets"),
            ],
            // Only the app has an icon; the widget extension's catalog holds just the mark.
            settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
        ),
        // The Mac app: the same views and the same core in one compact window that floats
        // above other apps. No widget extension — ⌘R, the Dictation menu and the
        // utterclip://record URL take the place of the iOS widget and control.
        .target(
            name: "UtterclipMac",
            destinations: [.mac],
            product: .app,
            productName: "Utterclip",
            bundleId: "com.ralfchille.voicer.mac",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Utterclip",
                "NSMicrophoneUsageDescription": "Used to record your voice for transcription.",
                "NSHumanReadableCopyright": "© 2026 Ralf Chille",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "ITSAppUsesNonExemptEncryption": false,
                "CFBundleURLTypes": [
                    ["CFBundleURLName": "com.ralfchille.voicer.mac", "CFBundleURLSchemes": ["utterclip"]],
                ],
            ]),
            sources: ["UtterclipMac/**/*.swift", "Utterclip/Views/**/*.swift"],
            resources: ["UtterclipMac/Resources/**"],
            // Sandboxed like a store app: microphone for recording, outbound network for the
            // one-time model download and the optional cloud rewrite. Nothing else.
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.security.device.audio-input": true,
                "com.apple.security.network.client": true,
            ]),
            dependencies: [
                .target(name: "UtterclipCore"),
                .package(product: "HighlightedTextEditor"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "MACOSX_DEPLOYMENT_TARGET": "14.0",
                // The iPhone-only family setting from the project base does not apply here.
                "TARGETED_DEVICE_FAMILY": "",
            ])
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
