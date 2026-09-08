# App Store release checklist — Utterclip 1.0

What is already in place, and what is left to do in App Store Connect and Xcode.
Paste-ready copy lives in [`listing.md`](listing.md); screenshots in [`screenshots/`](screenshots/).

## Done in the repo

- [x] **Privacy manifests** (`PrivacyInfo.xcprivacy`) in the app, the `UtterclipCore` framework and
      the widget extension. The stores use `UserDefaults`, a "required reason" API; the manifests
      declare reason `CA92.1` (app's own preferences), no tracking, no collected data. Without these,
      App Store Connect rejects the upload with ITMS-91053.
- [x] **Release archive builds and signs** with team `2F7QR8NL2D` (verified locally with
      `xcodebuild archive`; all three manifests present in the archive).
- [x] **Version 1.0, build 3.** Bump `CURRENT_PROJECT_VERSION` in `Project.swift` before every
      upload; App Store Connect refuses a build number it has already seen.
- [x] `ITSAppUsesNonExemptEncryption = NO` — no export-compliance prompt per build.
- [x] `NSMicrophoneUsageDescription` set; the app has no other permission prompts.
- [x] **Privacy policy** reachable without login at
      `https://github.com/ralfchille/utterclip-app/blob/main/PRIVACY.md`.
- [x] **6.9-inch screenshots** (1320 × 2868), five of them, in `screenshots/`. Sample content, light mode.
- [x] The app is fully usable without an API key (transcription + raw copy), so guideline 5.1.1
      (no forced sign-in / paid third-party account for core function) is satisfied.

## Before the first upload

- [ ] **Contact email** in `PRIVACY.md` (line near the end) and in the README Support section.
- [ ] **Apple Developer → Identifiers**: make sure `com.ralfchille.voicer` and
      `com.ralfchille.voicer.widgets` are registered as App IDs under team `2F7QR8NL2D`
      (Xcode's automatic signing usually did this already when the device builds were made). The
      framework's `com.ralfchille.voicer.core` needs no App ID.
- [ ] **App Store Connect → My Apps → +**: New App, iOS, name **Utterclip**, primary language
      English (U.S.), bundle ID `com.ralfchille.voicer`, SKU `utterclip-ios`. If the name is taken,
      App Store Connect says so here; the fallback is to keep "Utterclip" as the display name and
      pick a slightly longer App Store name (e.g. "Utterclip – Dictate & Paste").
- [ ] **Dictate a few German and English messages on the iPhone** with the current build to confirm
      the quantized `small_216MB` model is as accurate as the old one. The switch is one constant in
      `TranscriptionService.swift` if it is not.

## Upload

Either in Xcode: open `Utterclip.xcworkspace`, select **Utterclip → Any iOS Device (arm64)**,
**Product → Archive**, then in Organizer **Distribute App → App Store Connect → Upload**, accepting
the automatic signing.

Or from the terminal (after `mise exec tuist@4.200.5 -- tuist generate --no-open`):

```sh
xcodebuild archive -workspace Utterclip.xcworkspace -scheme Utterclip -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Utterclip.xcarchive -allowProvisioningUpdates
```

```sh
xcodebuild -exportArchive -archivePath build/Utterclip.xcarchive -exportPath build/export \
  -exportOptionsPlist docs/app-store/ExportOptions.plist -allowProvisioningUpdates
```

`ExportOptions.plist` (next to this file) uses `method = app-store-connect` with upload on, so
the second command uploads directly. The first upload of a new app can take 10–30 minutes to
finish processing before it appears under **TestFlight → iOS Builds**.

## In App Store Connect, per version

- [ ] **App Information**: categories (Productivity / Utilities), age rating questionnaire (all
      "No" → 4+), Privacy Policy URL.
- [ ] **Pricing and Availability**: Free, all territories (or your pick).
- [ ] **App Privacy**: answer *Data Not Collected* (rationale and fallback in `listing.md`).
- [ ] **1.0 Prepare for Submission**: paste promotional text, description, keywords, support URL,
      marketing URL, copyright, "What's New"; upload the five 6.9-inch screenshots in the order
      given in `listing.md`; select the processed build.
- [ ] **App Review Information**: paste the review notes from `listing.md`. Create a **fresh,
      low-limit API key** for the test-key line (Groq or Anthropic; set a small monthly cap), and
      **revoke it after approval**. Contact phone and email are required fields here too.
- [ ] **Sign-in required?** No. **Demo account?** None.
- [ ] Version release: **Manually release** for 1.0, so the README and GitHub links can be updated
      the moment it goes live.

## TestFlight first

- [ ] Add yourself as an internal tester and install 1.0 (3) on the iPhone 15 Pro. Check on the real
      device: first-launch model download, mic permission text, the Control Center control and the
      Action button, both widgets, the on-device engine toggle (iOS 26 + Apple Intelligence), one
      cloud rewrite per style, redaction round-trip with a phone number in the dictation,
      Continue dictating, silence auto-stop, History restore, editor save.
- [ ] Widget gallery shows the new build's widgets (build number was bumped, so previews re-render).

## After approval

- [ ] README: replace the two App Store placeholders with the real link
      (`https://apps.apple.com/app/id<APP_ID>`); delete or complete the TestFlight / IPA sections;
      fill the Support contact and the roadmap line.
- [ ] GitHub repo **Website** field → the App Store link.
- [ ] `git tag -a v1.0 -m "App Store release 1.0 (3)"` and push the tag; create a GitHub Release
      from it with the "What's New" text.
- [ ] Revoke the App Review test key.

## Known review-risk notes

- **Third-party trademarks** in the description (Slack, WhatsApp) are compatibility references
  and generally fine; they are deliberately absent from the keyword field.
- **Large first-launch download** from a third-party host is allowed (it is a Core ML model,
  data not code). The review notes explain it so the reviewer waits for it.
- **Bring-your-own-key** apps pass review as long as the app is useful without the key, which
  Utterclip is. Say so in the review notes (already in the template).
