# Voicer

Record → transcribe locally (Whisper) → raw text on the clipboard instantly → optionally
rewrite into a message style (Slack, email, WhatsApp, structured, summary) → styled text
replaces the clipboard.

Private v1, iOS 17+, German + English (auto-detected). Full spec in
[plan/voice-app-implementation-plan.md](plan/voice-app-implementation-plan.md).

## Project setup

The Xcode project is generated with [Tuist](https://tuist.dev) (installed via mise):

```sh
mise exec tuist@4.200.5 -- tuist generate
```

This creates `Voicer.xcworkspace` — open it, select the **Voicer** scheme, and run on a
device or simulator. WhisperKit is resolved via SPM automatically.

To run on a physical iPhone, set your development team on the Voicer target
(Signing & Capabilities) once after generating.

## First run

1. **Whisper model**: the multilingual `small` model (~500 MB) downloads on first launch
   and is cached. Afterwards the app warm-loads it at launch, so transcription starts
   instantly.
2. **API key** (for rewrites): open **Settings (gear) → Anthropic API key**, paste your
   key once. It is stored only in the device Keychain — never in this repo. Transcription
   and the raw-clipboard fast path work without a key; only the style rewrite needs it.

## Architecture

```
Voicer/
├─ VoicerApp.swift              # @main; warms the Whisper model at launch
├─ Models/                      # MessageStyle, style definitions, AppError
├─ Services/
│  ├─ AudioRecorder.swift       # 16 kHz mono WAV to a temp file
│  ├─ TranscriptionService.swift# always-warm WhisperKit singleton
│  ├─ Rewriter.swift            # protocol — cloud now, on-device MLX later
│  ├─ CloudRewriter.swift       # Anthropic Messages API (claude-haiku-4-5)
│  ├─ KeyProvider.swift         # Keychain-backed key storage
│  └─ Clipboard.swift
├─ ViewModels/RecorderViewModel.swift  # record → transcribe → copy raw → rewrite → copy
└─ Views/                       # ContentView, StylePickerRow, SettingsView, GlassBackground
```

Design: minimal black & white, Apple HIG, Liquid Glass on iOS 26+ with a
`.ultraThinMaterial` fallback on iOS 17–25 (single `glassBackground()` modifier).
