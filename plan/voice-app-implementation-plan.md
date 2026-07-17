# Voice → Transcribe → Rewrite iOS App — Implementation Plan

> A build-ready, stepped plan for an iOS app that records voice, transcribes it locally
> with Whisper, copies the raw transcript to the clipboard, then optionally rewrites the
> transcript into a chosen message style (Slack, email, WhatsApp, structured, summary) and
> copies the result. Written to be picked up and executed by Claude Code.

---

## 0. Product summary

**Core flow:** Record → Stop → Local Whisper transcribes → raw text copied to clipboard
immediately (fast path) → user picks a style → text is rewritten into that shape → rewritten
text replaces the clipboard.

**Confirmed by Ralf (v1):**

- Minimum iOS: **17**.
- Languages: **German + English** (multilingual `small`, auto-detect).
- Default one-tap style: **Slack to colleagues**.
- Style prompts: use Appendix A as-is (no tone changes for v1).
- Branding: **private app, no external design system.** Minimal black & white, Apple Human
  Interface Guidelines, **Liquid Glass** where available with graceful downward compatibility to
  iOS 17 (see §1a).

**Key decisions already made:**

- **Rewrite engine: hybrid.** Build cloud rewriter first behind a `Rewriter` protocol so an
  on-device (MLX) implementation can be swapped in later with no UI change.
- **Whisper model: multilingual `small`** (`openai_whisper-small`), auto language detection so
  German and English both work with no toggle.
- **Model loading: always-warm.** Load Whisper once at app launch, keep it resident, never
  reload per-recording.
- **API keys: Keychain**, accessed via a swappable `KeyProvider` so a user-supplied key can be
  added later without refactoring. The key is **never** committed to the repo (see §5a).
- **Rewrite model: `claude-haiku-4-5`** for v1 (fast, low cost; swap the model id to upgrade).
- **Whisper delivery: download-on-first-launch** (WhisperKit default; cached afterward).
- **Style picker UX: both.** A default style preset for one-tap use, plus a row of style
  buttons after the result to re-run the rewrite differently.

**Non-goals for v1:** on-device MLX rewriter (deferred), account system, cloud sync, sharing
extension. Design so these can be added later.

---

## 1. Tech stack & prerequisites

- **Language/UI:** Swift 5.9+, SwiftUI, `@Observable` (Observation framework).
- **Min iOS:** 17.0 (for `@Observable`). Drop to 16 only if needed (use `ObservableObject`).
- **Transcription:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) via Swift Package Manager.
- **Audio:** `AVFoundation` (`AVAudioRecorder` / `AVAudioEngine`).
- **Rewrite (cloud):** `URLSession` calling the Anthropic Messages API (or OpenAI — swappable).
- **Storage:** Keychain for API key; `UserDefaults` only for non-secret prefs (default style id).
- **Xcode:** 15+.

**Info.plist keys required:**

- `NSMicrophoneUsageDescription` — "Used to record your voice for transcription."

---

## 1a. Design & styling (minimal B/W + Liquid Glass with fallback)

**Direction:** Minimal, black-and-white, follows Apple Human Interface Guidelines. No custom
design system. Use system font (SF), system spacing, SF Symbols, respects Dark Mode automatically.

**Liquid Glass with downward compatibility (min iOS 17):**

Liquid Glass APIs (`.glassEffect()`, `GlassEffectContainer`) require **iOS 26+**. The app targets
iOS 17, so gate Liquid Glass behind availability checks and fall back to standard materials on
iOS 17–25. Centralize this in one reusable modifier so views stay clean:

```swift
import SwiftUI

/// Applies Liquid Glass on iOS 26+, falls back to an ultra-thin material otherwise.
struct GlassBackground: ViewModifier {
    var shape: some Shape = Capsule()
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)      // Liquid Glass
        } else {
            content.background(.ultraThinMaterial, in: shape)  // fallback
        }
    }
}

extension View {
    func glassBackground(shape: some Shape = Capsule()) -> some View {
        modifier(GlassBackground(shape: shape))
    }
}
```

Usage: `recordButton.glassBackground()` — one call site, correct on every OS version.

**Rules for the build:**

- Never call a Liquid Glass API without an `if #available(iOS 26.0, *)` guard.
- Prefer system materials (`.ultraThinMaterial`, `.regularMaterial`) for the fallback so the look
  stays cohesive with the glass version.
- Keep the palette monochrome: black/white + system grays; accent only via SF Symbols and the
  primary action button. Let system colors handle Dark Mode.
- Use SF Symbols for record/stop/copy/style icons; dynamic type + accessibility labels throughout.

## 2. Target project structure

```
Voicer/
├─ VoicerApp.swift            # @main; kicks off model warm-up
├─ Models/
│  ├─ MessageStyle.swift            # style data model
│  ├─ Styles.swift                  # default style definitions
│  └─ AppError.swift                # shared error types
├─ Services/
│  ├─ AudioRecorder.swift          # record/stop → temp .wav
│  ├─ TranscriptionService.swift   # warm-load WhisperKit singleton
│  ├─ Rewriter.swift               # protocol + errors
│  ├─ CloudRewriter.swift          # Anthropic/OpenAI implementation
│  ├─ KeyProvider.swift            # Keychain-backed key source (swappable)
│  └─ Clipboard.swift              # UIPasteboard wrapper
├─ ViewModels/
│  └─ RecorderViewModel.swift      # orchestrates the full flow
├─ Views/
│  ├─ ContentView.swift            # main record screen
│  ├─ StylePickerRow.swift         # style buttons
│  └─ SettingsView.swift           # default style + (future) API key field
└─ Resources/
   └─ (bundled Whisper model files)
```

---

## Phase 1 — Project setup & permissions

**Goal:** A running SwiftUI app with mic permission and SPM dependencies.

**Steps:**

1. Create a new SwiftUI iOS app target named `Voicer`, min deployment iOS 17.
2. Add WhisperKit via SPM (`https://github.com/argmaxinc/WhisperKit`).
3. Add `NSMicrophoneUsageDescription` to Info.plist.
4. Create the folder groups from §2.
5. Add `AppError.swift` with a shared error enum used across services.

**Acceptance criteria:** App builds and launches on a device; requesting mic permission shows
the system prompt.

---

## Phase 2 — Audio capture

**Goal:** Record audio and produce a 16 kHz mono `.wav` in a temp location.

**Steps:**

1. Implement `AudioRecorder` (`@Observable`) with `start()` and `stop() -> URL`.
2. Configure the `AVAudioSession` category `.record`, request permission.
3. Record to a temp `.wav`, PCM, **16 kHz, mono** (Whisper's expected format).
4. Expose `isRecording` state for the UI.

**Acceptance criteria:** Tapping record then stop yields a playable `.wav` at the returned URL
with the correct sample rate/channel count.

---

## Phase 3 — Local transcription (warm-load)

**Goal:** Whisper `small` model loaded once at launch, transcribes the recorded file.

**Model delivery — pick one (see "What I need from you"):**

- **A) Download-on-first-launch (WhisperKit default):** simplest; smaller app binary; needs
  network the first time and shows a one-time download progress state. Cached afterward.
- **B) Bundle the model in the app:** no network ever; larger binary (~500MB for `small`);
  requires manually adding the converted model files and pointing `WhisperKitConfig(modelFolder:)`
  at them. More build setup.

The reference below uses **A**. Either way, the *runtime load* (into memory) is what the
always-warm trick removes on every recording; the *download* is a one-time cost.

**Steps:**

1. Choose model delivery (A or B above). Default: A.
2. Implement `TranscriptionService` as a singleton `@Observable` with a `State` enum
   (`cold, warming, ready, failed`) and:
   - `warmUp()` — idempotent, loads + compiles the model in a background `Task`.
   - `transcribe(_ audioURL:) async throws -> String`.
3. Call `TranscriptionService.shared.warmUp()` from `VoicerApp.init()`.
4. In the UI, bind the record button's enabled state to `state == .ready`; show a subtle
   "warming up…" indicator only if the user beats the load.

**Reference implementation:**

```swift
import WhisperKit
import Observation

@Observable
final class TranscriptionService {
    static let shared = TranscriptionService()
    private var whisperKit: WhisperKit?
    private(set) var state: State = .cold
    enum State: Equatable { case cold, warming, ready, failed(String) }
    private init() {}

    func warmUp() {
        guard case .cold = state else { return }
        state = .warming
        Task {
            do {
                // Current WhisperKit API: configure via WhisperKitConfig.
                // By default WhisperKit downloads the model from HuggingFace on first
                // run and caches it; subsequent launches load from cache.
                // model: "small" resolves to the multilingual openai_whisper-small variant.
                let config = WhisperKitConfig(model: "small")
                let kit = try await WhisperKit(config)
                self.whisperKit = kit           // model is loaded & ready
                self.state = .ready
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        guard let kit = whisperKit else { throw AppError.modelNotReady }
        let results = try await kit.transcribe(audioPath: audioURL.path)
        return results.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Acceptance criteria:** First launch compiles the model once (cached thereafter); after warm-up,
transcription of a short clip returns text with no per-recording load delay. Multilingual input
(e.g. German) transcribes correctly without a language toggle.

---

## Phase 4 — Clipboard fast path

**Goal:** Raw transcript is on the clipboard the instant transcription completes.

**Steps:**

1. Implement `Clipboard.copy(_ string:)` wrapping `UIPasteboard.general.string`.
2. In the flow (Phase 7), copy the raw transcript immediately after transcription — before any
   rewrite — so the user is never blocked by the rewrite step.

**Acceptance criteria:** After stopping a recording, pasting elsewhere yields the raw transcript
without waiting for any network call.

---

## Phase 5 — Rewrite engine (protocol + cloud + styles)

**Goal:** Rewrite raw transcript into a chosen style via a swappable engine.

**Steps:**

1. Define `MessageStyle` and the `Rewriter` protocol.
2. Define the default styles in `Styles.swift` (each is a system prompt).
3. Implement `CloudRewriter` using `URLSession` + Anthropic Messages API, reading the key via
   `KeyProvider`.
4. Implement `KeyProvider` backed by Keychain, exposing a closure/source so a user-entered key
   can replace the dev key later without changing call sites.

**Data models:**

```swift
struct MessageStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let systemPrompt: String
}

protocol Rewriter {
    func rewrite(_ text: String, style: MessageStyle) async throws -> String
}
```

**Default styles** — all end with "output only the message" (clean paste) and "preserve the
original language" (multilingual correctness):

- **Slack to colleagues** (`slack`, 💬): concise, professional-but-friendly, no greeting/sign-off.
- **Email** (`email`, ✉️): subject line, greeting, body, polite closing.
- **WhatsApp casual** (`whatsapp`, 📱): warm, relaxed, natural, light emoji if it fits.
- **Structured answer** (`structured`, 🗂️): intro, clear points/bullets, brief conclusion.
- **Summary** (`summary`, 📝): one-line takeaway + 3–6 bullets for a summary channel.

Full prompt strings are in Appendix A.

**Cloud rewriter reference:**

```swift
struct CloudRewriter: Rewriter {
    let keyProvider: () -> String?   // dev key now; user key later

    func rewrite(_ text: String, style: MessageStyle) async throws -> String {
        guard let apiKey = keyProvider() else { throw AppError.noApiKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": style.systemPrompt,
            "messages": [["role": "user", "content": text]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.rewriteFailed
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = (json?["content"] as? [[String: Any]])?
                .first?["text"] as? String else { throw AppError.rewriteFailed }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

> Note: keep the model id and provider behind the `Rewriter` protocol. Later, add
> `LocalRewriter` (MLX) conforming to the same protocol. Be mindful that a resident Whisper model
> **plus** a resident local LLM is heavy on older devices — another reason cloud is the v1 default.

**Acceptance criteria:** Given a raw transcript and a style, `CloudRewriter` returns clean,
paste-ready text in the transcript's language; missing/invalid key surfaces a clear error.

---

## 5a. Where the API key goes (repo-safe handling)

**Rule: the key never touches git.** Add a `.gitignore` before the first commit and keep secrets
out of tracked files. Recommended flow for a private repo:

**Recommended — enter once into Keychain via a dev Settings field (nothing in the repo):**

1. Build a small Settings screen with a secure text field bound to `KeyProvider`.
2. On first run, paste the key there; `KeyProvider` writes it to the **Keychain**.
3. It persists on the device; the repo stays clean. This is also the exact path future
   user-supplied keys will use — so you build it once.

**Alternative — local `Secrets.xcconfig` (convenience for dev builds):**

1. Create `Secrets.xcconfig` containing `ANTHROPIC_API_KEY = sk-ant-...`.
2. Add `Secrets.xcconfig` to `.gitignore` (commit a `Secrets.example.xcconfig` with a blank value
   as a template).
3. Reference it from the build config; at first launch, read it and move the value into Keychain,
   then rely on Keychain thereafter.

**`.gitignore` must include (at minimum):**

```
Secrets.xcconfig
*.xcuserstate
xcuserdata/
.DS_Store
```

**Never do:** commit the key in source, in `Info.plist`, in a build setting that's tracked, or in
any README. If a key is ever committed, revoke it immediately — git history keeps it forever.

**So, to answer "where do I put it":** once the repo is set up, put it **in the app's Keychain via
the Settings field on first run** (recommended) — not in any file in the repo.

## Phase 6 — Style picker UX ("both")

**Goal:** One-tap default flow, plus re-run with a different style after seeing the result.

**Steps:**

1. Add a **default style** preference (store style `id` in `UserDefaults`), edited in `SettingsView`.
   Default value for v1: **`slack`** (Slack to colleagues).
2. After transcription, auto-run the rewrite with the default style (spinner on the rewrite only).
3. Show the rewritten text and a `StylePickerRow` of style buttons; tapping one re-runs the
   rewrite for that style and re-copies the result.
4. Always keep the raw transcript recoverable (a "copy raw" action) in case the rewrite isn't wanted.

**Acceptance criteria:** Default-style path is a single tap from stop → styled text on clipboard;
tapping another style re-rewrites and updates the clipboard; raw transcript remains accessible.

---

## Phase 7 — Orchestration & main screen

**Goal:** Tie the modules together in a `RecorderViewModel` and `ContentView`.

**Steps:**

1. `RecorderViewModel` (`@Observable`) exposes: `phase` (idle, recording, transcribing,
   rewriting, done, error), `rawTranscript`, `styledText`, `selectedStyle`.
2. Flow: `record()` → `stopAndProcess()` → transcribe → **copy raw immediately** → rewrite with
   default style → copy styled → set `phase = .done`.
3. `rewrite(with style:)` for manual re-runs from the button row.
4. `ContentView`: big record/stop button (bound to transcription `state` and `phase`), result
   text area, `StylePickerRow`, and a spinner during `rewriting`.
5. Handle each error phase with a readable message and a retry affordance.

**Acceptance criteria:** End-to-end: launch → (model warms in background) → record → stop → raw
copied → styled result shown and copied → switch styles freely. Errors never leave the UI stuck.

---

## Phase 8 — Polish & QA

**Steps:**

1. Test on a real device (loading time, latency) — not just the simulator.
2. Verify multilingual: record German and English, confirm correct transcription and that the
   rewrite preserves language.
3. Verify the raw transcript is on the clipboard before the rewrite completes.
4. Handle edge cases: empty/very short recording, no network (rewrite fails gracefully, raw still
   copied), model load failure.
5. Haptics on record start/stop; accessible labels on buttons.
6. Confirm Keychain read/write path works and no key is logged.

**Acceptance criteria:** All above pass on device; app is usable offline for transcription (rewrite
degrades gracefully).

---

## Future work (design-for, don't build in v1)

- **On-device MLX rewriter** conforming to `Rewriter` (privacy/offline; watch memory footprint).
- **User-supplied API key** field in Settings, written to Keychain via existing `KeyProvider`.
- **Custom user styles** (persist user-added `MessageStyle`s).
- **Share sheet / keyboard extension** for pasting into any app faster.
- Model size option in Settings (`base` vs `small`) for speed/quality trade-off.

---

## Appendix A — Full style system prompts

**Slack to colleagues:**
> Rewrite the transcript as a clear, concise Slack message to work colleagues. Professional but
> friendly. Fix grammar and filler words. Keep it brief, use short paragraphs, no greeting or
> sign-off. Preserve the original language. Output only the message.

**Email:**
> Rewrite the transcript as a well-structured email. Add a suitable subject line, a brief
> greeting, clear body paragraphs, and a polite closing. Correct grammar and remove filler. Keep
> the original language. Output subject then body.

**WhatsApp casual:**
> Rewrite the transcript as a warm, casual WhatsApp message to a close family member or friend.
> Natural, relaxed tone; light contractions; emojis only if they fit naturally. Fix obvious errors
> but keep it sounding like me. Preserve the original language. Output only the message.

**Structured answer:**
> Turn the transcript into a well-organized, structured response. Use a short intro, then clear
> points (headings or bullets where helpful), then a brief conclusion if warranted. Correct
> grammar, keep it precise. Preserve the original language. Output only the formatted answer.

**Summary:**
> Summarize the transcript into its key points as a concise digest suitable for a summary channel.
> Lead with a one-line takeaway, then 3–6 short bullets of the essentials. Drop filler and
> repetition. Preserve the original language. Output only the summary.

---

## Appendix B — Suggested build order for Claude Code

1. Phase 1 (setup) → confirm build.
2. Phases 2–4 (record → transcribe → copy raw): reproduces the base video behavior.
3. Phase 5 (rewrite protocol + cloud + one style) → verify one rewrite works.
4. Phase 6–7 (style picker + orchestration) → full flow.
5. Phase 8 (polish/QA).
6. Then optionally pick up Future work.
