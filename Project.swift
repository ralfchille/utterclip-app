import ProjectDescription

/// Shared by the iPhone and Mac apps so they meet in the same CloudKit container and the same
/// keychain access group. The widget extension needs none of it. (No key-value store: it rides
/// on iCloud Drive, which managed Macs can have switched off; settings use CloudKit instead.)
let iCloudEntitlements: [String: Plist.Value] = [
    "com.apple.developer.icloud-container-identifiers": ["iCloud.com.ralfchille.voicer"],
    "com.apple.developer.icloud-services": ["CloudKit"],
    "keychain-access-groups": ["$(AppIdentifierPrefix)com.ralfchille.voicer.shared"],
]

/// CloudKit delivers change notifications over push. The key differs per platform; Xcode
/// flips the value to "production" for App Store / TestFlight exports.
let iOSPushEntitlement: [String: Plist.Value] = ["aps-environment": "development"]
let macPushEntitlement: [String: Plist.Value] = ["com.apple.developer.aps-environment": "development"]

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
            "MARKETING_VERSION": "1.1",
            "CURRENT_PROJECT_VERSION": "4",
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
                // Read at runtime to name the shared keychain access group ("<TeamID>.…").
                "UtterclipAppIdentifierPrefix": "$(AppIdentifierPrefix)",
                "NSMicrophoneUsageDescription": "Used to record your voice for transcription.",
                "UILaunchScreen": [:],
                // CloudKit wakes the app with a silent push when another device changed history.
                "UIBackgroundModes": ["remote-notification", "fetch"],
                // Wakes the app to pre-load the Whisper model; see WarmUpScheduler.
                "BGTaskSchedulerPermittedIdentifiers": ["com.ralfchille.voicer.warm"],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "ITSAppUsesNonExemptEncryption": false,
                // utterclip://record — the widget and control open the app into a recording.
                "CFBundleURLTypes": [
                    ["CFBundleURLName": "com.ralfchille.voicer", "CFBundleURLSchemes": ["utterclip"]],
                ],
            ]),
            sources: ["Utterclip/**/*.swift"],
            resources: ["Utterclip/Resources/**"],
            // iCloud sync (plan/1.1-icloud-sync.md): one CloudKit container and one key-value
            // store shared with the Mac app, a keychain access group both apps can see so the
            // API key syncs through iCloud Keychain, and push so CloudKit can signal changes.
            entitlements: .dictionary(iCloudEntitlements.merging(iOSPushEntitlement) { current, _ in current }),
            dependencies: [
                .target(name: "UtterclipCore"),
                .package(product: "HighlightedTextEditor"),
                .target(name: "UtterclipWidgets"),
            ],
            // Icon Composer document (Utterclip/Resources/Utterclip.icon), shared with the Mac
            // app: iOS 26 renders it as a Liquid Glass icon, Xcode derives the classic icon for
            // iOS 17–25. The widget extension's catalog holds just the mark.
            settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "Utterclip"])
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
                "UtterclipAppIdentifierPrefix": "$(AppIdentifierPrefix)",
                // Menu bar app: no Dock tile, no app-switcher entry; the status item is the app.
                "LSUIElement": true,
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
            ].merging(iCloudEntitlements) { current, _ in current }
             .merging(macPushEntitlement) { current, _ in current }),
            dependencies: [
                .target(name: "UtterclipCore"),
                .package(product: "HighlightedTextEditor"),
            ],
            settings: .settings(base: [
                // The same Icon Composer document as the iPhone app (UtterclipMac/Resources/
                // Utterclip.icon): macOS 26 renders it as a Liquid Glass icon, Xcode derives
                // the classic icon for macOS 14/15.
                "ASSETCATALOG_COMPILER_APPICON_NAME": "Utterclip",
                "MACOSX_DEPLOYMENT_TARGET": "14.0",
                // The iPhone-only family setting from the project base does not apply here.
                "TARGETED_DEVICE_FAMILY": "",
                // Xcode's macOS default is "-" (sign to run locally): an ad-hoc signature
                // that changes with every build, so macOS treats each build as a new app —
                // microphone permission and keychain access get asked for again and again.
                // The team's development certificate gives the app one stable identity.
                "CODE_SIGN_IDENTITY": "Apple Development",
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
