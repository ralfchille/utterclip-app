# Reply to App Review — Guideline 2.1, Information Needed (1.0, build 3)

Apple asked for six items because the developer account has little review history. Post the
text below as the reply in App Store Connect (**App Review → the message thread → Reply**),
and paste the same text into **App Review Information → Notes** on the version page, as they
request. Item 1 is a screen recording you make on the iPhone; the shot list is at the end.

---

**1. Screen recording**

Attached: a screen recording made on an iPhone 15 Pro running iOS 26, starting from the app
launch and showing the complete user flow (recording, on-device transcription, clipboard copy,
style rewrite, switching styles, editing, history, settings). The app has no account
registration, login or account deletion, no user-generated content that is shared with other
users, and no paid content or in-app purchases.

**2. Purpose and target audience**

Utterclip is a dictation utility for people who send many short written messages and would
rather speak them. The problem: dictation produces text in the shape of speech — filler words,
no punctuation, no structure — which is not what anyone would send. Utterclip transcribes speech
on the iPhone itself, copies the raw transcript to the clipboard immediately, then rewrites it
in a style the user picks (a Slack-style team message, a WhatsApp-style personal message, an
email, a structured prompt for an AI assistant, or plain auto-correction) and copies that. The
user switches to their messaging app and pastes. Target audience: knowledge workers and anyone
who prefers talking to typing on a phone; adults; English and German speakers primarily. The
app is free, has no ads, no subscriptions and no in-app purchases, and its source code is
published under the MIT license at https://github.com/ralfchille/utterclip-app.

**3. Setup and access instructions**

No login, credentials or sample files are needed.

1. Launch the app. On first launch it downloads a ~220 MB speech-recognition model (OpenAI
   Whisper, via the open-source WhisperKit library) from huggingface.co and caches it. A
   spinner and "Model loads in the background" are shown; this takes about a minute on Wi-Fi.
2. Allow microphone access when prompted.
3. Tap the microphone button, speak a sentence, tap again (or stop speaking; five seconds of
   silence ends the recording). The transcript appears and is copied to the clipboard.
   Transcription runs entirely on the device.
4. The styled rewrite (default style "Slack") needs one of two engines, chosen in Settings
   (gear icon, top right):
   a) **On device**: Settings → Rewrite engine → "Rewrite on device (Apple Intelligence)". Works
      on iPhones with Apple Intelligence enabled (iOS 26); no key, no network.
   b) **Cloud**: Settings → AI provider API key → paste a key. For review we provide this test
      key (Groq / Anthropic; low spending cap; revoked after review):
      <<< PASTE THE TEST KEY >>>
      The provider is detected from the key; the key is stored in the iOS Keychain and sent
      only to that provider.
5. Tap another style pill (Plain, WhatsApp, Prompt, Email) to re-run the rewrite; each result
   is copied to the clipboard. "Edit" opens an editor for the transcript or the result;
   "Copy raw" re-copies the unstyled transcript; the clock icon (top left) opens History.
6. Optional: the "Dictate" Home Screen / Lock Screen widget and the Control Center control
   (iOS 18+) open the app directly into a recording.

**4. External services, tools and platforms**

- **Hugging Face (huggingface.co)** — one-time download of the Whisper speech-recognition model
  published by Argmax (repository argmaxinc/whisperkit-coreml). Only a file download; no user
  data is sent.
- **WhisperKit** (open source, Argmax) — on-device speech recognition library. Runs locally;
  no network use other than the model download above.
- **Apple Foundation Models (Apple Intelligence)** — optional on-device text rewriting on
  iOS 26. No network.
- **AI text-rewriting providers, optional and user-configured**: Anthropic (api.anthropic.com),
  OpenAI (api.openai.com), Google Gemini (generativelanguage.googleapis.com), Groq
  (api.groq.com). Used only if the user enters their own API key for one of them; the app then
  sends the transcript text plus the style instruction to that provider over HTTPS and receives
  the rewritten text. Personal data such as emails, phone numbers, links and addresses are
  replaced with placeholders before sending (on by default) and restored in the result.
- No analytics, advertising, crash-reporting, authentication or payment services. The app has
  no server of its own. Full privacy policy:
  https://github.com/ralfchille/utterclip-app/blob/main/PRIVACY.md

**5. Regional differences**

None. The app functions identically in all regions. Speech recognition detects the spoken
language automatically (English and German are the tested languages). Availability of the
optional on-device rewriting engine follows Apple Intelligence availability on the device;
where it is unavailable, the app says so in Settings and the cloud engine or plain transcription
remain available.

**6. Regulated industry / protected material**

Not applicable. Utterclip does not operate in a regulated industry and contains no protected
third-party material. Whisper (OpenAI) and WhisperKit (Argmax) are open-source, MIT-licensed
components used under their licenses.

---

## Short version for the reply field (App Store Connect caps replies at 4000 characters)

Paste this in the message thread; the long version above fits in App Review Information → Notes, which has no such cap.

```
1. SCREEN RECORDING: attached, made on an iPhone 15 Pro (iOS 26), starting from app launch and showing the full flow: recording, on-device transcription, clipboard copy, style rewrite, switching styles, editing, history, settings. The app has no account registration, login or deletion, no user-generated content shared with others, and no paid content or in-app purchases.

2. PURPOSE: Utterclip is a dictation utility for people who send many short messages and would rather speak them. Dictation yields the shape of speech (filler words, no punctuation, no structure), not something one would send. Utterclip transcribes speech on the iPhone, copies the raw transcript to the clipboard at once, then rewrites it in a style the user picks (Slack-style team message, WhatsApp-style personal message, email, structured AI prompt, or plain auto-correction) and copies that. The user pastes it into their messaging app. Audience: adults who prefer talking to typing, mainly English and German speakers. Free, no ads, no subscriptions or IAP; source code is public under MIT at https://github.com/ralfchille/utterclip-app

3. SETUP: no login, credentials or sample files needed.
a) First launch downloads a ~220 MB speech model (OpenAI Whisper via the open-source WhisperKit library) from huggingface.co; allow about a minute on Wi-Fi.
b) Allow microphone access.
c) Tap the mic, speak a sentence, tap again (or stop talking; 5 s of silence ends the recording). The transcript appears and is copied. Transcription is fully on-device.
d) The styled rewrite (default "Plain") needs one of two engines, chosen in Settings (gear icon): "Rewrite on device (Apple Intelligence)" on iPhones with Apple Intelligence (iOS 26), no key, no network; or "AI provider API key": paste this test key (low spending cap, revoked after review): <<< TEST KEY >>>  The provider is detected from the key; the key is kept in the iOS Keychain and sent only to that provider.
e) Tap another style pill (Plain, WhatsApp, Prompt, Email) to re-run; each result is copied. "Edit" opens an editor, "Copy raw" re-copies the transcript, the clock icon opens History. The "Dictate" widget/Control Center control (iOS 18+) opens the app into a recording.

4. EXTERNAL SERVICES: Hugging Face (huggingface.co), a one-time download of the Whisper model published by Argmax, no user data sent. WhisperKit (open source, Argmax), on-device speech recognition. Apple Foundation Models (Apple Intelligence), optional on-device rewriting, no network. Optional, user-configured AI text providers: Anthropic (api.anthropic.com), OpenAI (api.openai.com), Google Gemini (generativelanguage.googleapis.com), Groq (api.groq.com): used only if the user enters their own key; the app then sends the transcript text plus the style instruction over HTTPS and receives the rewritten text; emails, phone numbers, links and addresses are replaced with placeholders before sending (on by default) and restored afterwards. No analytics, ads, crash reporting, authentication or payment services; no server of our own. Privacy policy: https://github.com/ralfchille/utterclip-app/blob/main/PRIVACY.md

5. REGIONAL DIFFERENCES: none; the app works identically in all regions. Spoken language is detected automatically (English and German tested). The optional on-device engine follows Apple Intelligence availability; where unavailable, Settings says so and the cloud engine or plain transcription remain available.

6. REGULATED INDUSTRY / PROTECTED MATERIAL: not applicable. Whisper (OpenAI) and WhisperKit (Argmax) are open-source, MIT-licensed components used under their licenses.
```

---

## Shot list for the screen recording (item 1)

Record on the iPhone 15 Pro with the TestFlight build 3, iOS 26, in **Settings → Control
Center → Screen Recording**. Aim for 60–90 seconds; no narration needed. Before recording,
make sure the model is already downloaded, the app is force-quit, and either the on-device
engine is on or your real key is saved (a key is never shown on screen).

1. Home Screen → tap the Utterclip icon (the recording must start with the launch).
2. Tap the mic, speak one English sentence with a filler word or two, tap the mic again.
3. Wait for the transcript and the "Copied — Slack" result to appear.
4. Tap the **Prompt** pill, then **Email**, showing a different rewrite each time.
5. Tap **Edit** on the raw transcript, change a word, tap **Done** — the rewrite re-runs.
6. Open **History** (clock icon), tap an earlier entry, close.
7. Open **Settings** (gear), scroll once through the styles, the API key section (empty or
   masked) and the engine toggle, tap **Done**.
8. Switch to Notes or Messages and paste, to show the clipboard result. Stop the recording.

Trim the ends in Photos, then attach the video in the App Store Connect reply (the message
thread accepts attachments up to about 500 MB; if it is larger, AirDrop it to the Mac and
compress with QuickTime → Export → 720p).
