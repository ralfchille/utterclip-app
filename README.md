# Utterclip

Dictate, and polished text lands on your clipboard.

Tap the mic, speak, tap again. Utterclip transcribes **on-device** (Whisper), puts the raw
text on the clipboard instantly, then rewrites it in the style you pick — a Slack message,
a WhatsApp reply, an email, a prompt for an AI assistant, or just auto-corrected — and
copies that instead. Minimal, monochrome, iOS-native.

## Features

- **On-device transcription** with [WhisperKit](https://github.com/argmaxinc/WhisperKit)
  (multilingual `small` model). German and English are auto-detected; audio never leaves
  the phone.
- **Instant clipboard**: the raw transcript is pasteable before any rewrite starts.
- **Rewrite styles** — Plain (auto-correct only), Slack, WhatsApp, Prompt (structured as
  *The job / The why / The guardrails / Done means*) and Email. Edit any prompt, rename or
  delete the defaults (restorable), add your own — up to 7 styles.
- **Two rewrite engines**, chosen in Settings:
  - **Cloud** — paste one API key; the provider is detected from its prefix:
    Anthropic (`sk-ant-`), OpenAI (`sk-`), Google Gemini (`AIza`), Groq (`gsk_`).
  - **On-device** — Apple's Foundation Models (iOS 26, Apple Intelligence). No key, nothing
    leaves the phone; a notch below the cloud models, best for lighter styles.
- **Privacy redaction** (cloud only, on by default): emails, phone numbers, links and
  addresses are swapped for placeholders before the text is sent, and restored in the
  result. Names are left alone — detecting them is unreliable and they carry tone.
- **Continue dictating**: append to the current transcript; the style re-runs on the whole
  text.
- **Hands-free stop**: the recording ends on its own after 5 seconds of silence (once
  you've started talking), then transcribes and rewrites as if you had tapped stop.
- **History** of past dictations with one-tap restore; **markdown or plain-text** copy
  mode; an in-app **editor** for quick fixes; a live **waveform** while recording.
- **Widget & control**: a Home Screen widget, a circular Lock Screen widget, and an iOS 18
  Control Center / Action button control that open the app straight into a recording.

## Requirements

- Xcode 26 (iOS 26 SDK) and an iPhone on iOS 17 or later.
  On-device rewriting needs iOS 26 with Apple Intelligence; the control needs iOS 18.
- [mise](https://mise.jdx.dev) — the project file is generated with
  [Tuist](https://tuist.dev), pinned via mise.

## Setup

```sh
git clone https://github.com/ralfchille-babbel/utterclip-app.git
cd utterclip-app
mise exec tuist@4.200.5 -- tuist generate
```

This resolves the Swift packages and creates `Utterclip.xcworkspace` — open it and run the
**Utterclip** scheme on a simulator or device.

To run on your own iPhone, change `DEVELOPMENT_TEAM` and the two `bundleId`s in
[`Project.swift`](Project.swift) to your Apple Developer team and identifiers, then
regenerate. (The checked-in values belong to the original author's account.)

## First run

1. **Whisper model** — the ~500 MB `small` model downloads once from Hugging Face and is
   cached; afterwards it warm-loads at launch. You can record while it loads.
2. **Rewrites** — either paste an API key in **Settings → AI provider API key**, or turn on
   **Settings → Rewrite engine → Rewrite on device**. Without either, you still get the raw
   transcript on the clipboard.

## Privacy

- Audio is transcribed on-device and the recording is deleted right after.
- With the on-device engine, nothing ever leaves the phone.
- With a cloud engine, only the transcript text (redacted, if enabled) and the style prompt
  are sent to the provider you chose, authenticated with your own key. The app attaches no
  identifiers of its own.
- The API key lives in the device Keychain; history is a local JSON file in the app's
  container.

## Architecture

```
Utterclip/
├─ UtterclipApp.swift            # @main; warms the Whisper model at launch
├─ Models/                       # MessageStyle, built-in Styles, HistoryEntry, AppError
├─ Services/
│  ├─ AudioRecorder.swift        # 16 kHz mono WAV + live level metering
│  ├─ TranscriptionService.swift # always-warm WhisperKit singleton
│  ├─ Rewriter.swift             # protocol both engines implement
│  ├─ RewritePrompt.swift        # the shared "rephrase, never respond" contract
│  ├─ CloudRewriter.swift        # cloud engine
│  ├─ AIProvider.swift           # provider detection, endpoints, request/response shapes
│  ├─ LocalRewriter.swift        # Apple Foundation Models engine (iOS 26)
│  ├─ Redactor.swift             # reversible placeholder redaction (NSDataDetector)
│  ├─ StyleStore.swift           # built-in overrides, custom styles, deletions
│  ├─ HistoryStore.swift         # dictation log
│  ├─ KeyProvider.swift          # Keychain-backed key storage
│  └─ Clipboard.swift
├─ ViewModels/RecorderViewModel.swift  # record → transcribe → copy → rewrite → copy
└─ Views/                        # ContentView, StylePickerRow, HistoryView, SettingsView,
                                 # EditorView, WaveformView, MarkdownView, GlassBackground
UtterclipWidgets/                # widget bundle: Home/Lock Screen widget + Control
```

Design: black & white, Apple HIG, Liquid Glass on iOS 26 with a material fallback on
iOS 17–25 (one `glassBackground()` modifier). Original design notes live in
[`plan/`](plan/).

## License

[MIT](LICENSE) — free to use, modify and redistribute.
