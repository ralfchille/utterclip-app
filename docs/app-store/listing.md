# App Store listing copy — Utterclip 1.0

Paste-ready text for App Store Connect. Character limits are Apple's; counts are given
where a field is tight. Trademark note: Slack and WhatsApp are named in the description as
apps the output is *for* (allowed as compatibility references) but kept **out of the keyword
list**, where other companies' trademarks tend to get flagged under guideline 2.3.7.

## App information

| Field | Value |
|---|---|
| Name (30) | `Utterclip` |
| Subtitle (30) | `Dictate. Paste polished text.` |
| Primary category | Productivity |
| Secondary category | Utilities |
| Bundle ID | `com.ralfchille.voicer` (kept from the Voicer days so Keychain + history survive) |
| SKU | `utterclip-ios` |
| Primary language | English (U.S.) |
| Copyright | `2026 Ralf Chille` |
| Age rating | 4+ (answer **No** to every content question; no unrestricted web access, no user-generated content shared with others) |
| Price | Free, no in-app purchases |
| Support URL | `https://github.com/ralfchille/utterclip-app/issues` |
| Marketing URL | `https://github.com/ralfchille/utterclip-app` |
| Privacy Policy URL | `https://github.com/ralfchille/utterclip-app/blob/main/PRIVACY.md` |

## Promotional text (170)

```
Speak, and a clean Slack message, WhatsApp reply, email or AI prompt lands on your clipboard. Transcribed on your iPhone. No account: bring your own key or go on-device.
```

## Description (4000)

```
Typing on a phone is slow. Talking is fast. But what comes out of dictation isn't what you'd send: filler words, no punctuation, the shape of speech instead of the shape of a message.

Utterclip closes that gap in one tap.

Tap the mic, say what you mean, tap again — or just stop talking, it notices. Your words are transcribed right on your iPhone and land on the clipboard instantly. Then they're rewritten in the style you pick and copied again: a Slack message to your team, a WhatsApp reply to a friend, an email, a structured prompt for an AI assistant, or simply auto-corrected. Switch apps, paste, done.

DICTATION
• Transcription runs on your iPhone with OpenAI's Whisper model. Audio never leaves the device.
• The raw transcript is on your clipboard before any rewrite starts.
• Hands-free: five seconds of silence ends the recording.
• Continue dictating to append to what you just said.
• Language is detected automatically; English, German and French are the tested ones.

REWRITING
• Five built-in styles: Plain, Slack, WhatsApp, Prompt, Email.
• Edit any prompt, rename or delete the defaults, add your own — up to seven.
• Pick the style before you record, or re-run with another one after.
• The app rewrites. It never answers. A question stays a question.
• Same language in, same language out.

TWO ENGINES, YOUR CHOICE
• On device: Apple Intelligence (iOS 26, supported iPhones). No key, nothing leaves the phone.
• Cloud: paste one API key from Anthropic, OpenAI, Google Gemini or Groq. The provider is detected from the key. Fast, inexpensive models; you pay the provider cents per month for short messages.

PRIVACY BY DESIGN
• No account, no analytics, no tracking, no server of ours.
• With the cloud engine, emails, phone numbers, links and addresses are swapped for placeholders before the text is sent and restored in the result.
• Your API key lives in the Keychain and goes only to its provider.
• History stays on your phone. Clear it any time.

EVERYTHING ELSE
• History with one-tap restore.
• Editor for quick fixes; saving re-copies.
• Markdown or plain-text copy mode.
• Home Screen and Lock Screen widgets, plus a Control Center / Action button control that opens straight into a recording.
• Minimal, monochrome, native. Liquid Glass on iOS 26.

Utterclip is free and open source (MIT). The code is public — every privacy claim can be checked.

The speech model (about 220 MB) downloads once on first launch; Wi-Fi recommended. Rewrites need either an iPhone with Apple Intelligence or your own API key. Without either you still get the raw transcript on your clipboard after every recording.

Utterclip is not affiliated with Slack, WhatsApp, Apple, OpenAI, Anthropic, Google or Groq.
```

## Keywords (100, comma-separated)

```
dictation,voice to text,speech to text,whisper,transcribe,clipboard,rewrite,email,message,prompt,ai
```

## What's New in This Version

1.0 shipped with `Initial release.` — the text below is for **1.1**.

```
Dictate on the iPhone, pick it up on the Mac.

• iCloud sync. Your history, your styles, your settings and your API key travel between your own devices, inside your own iCloud account — never through a server of ours. One switch in Settings turns it off.
• Fix a word where it sits. Tap the result and type: the cursor lands where you tapped, and the corrected text is on the clipboard as you go.
• Give the Action button to Utterclip and it opens recording: Settings → Action Button → Shortcut → Start dictating. (iPhone 15 Pro and later.)
• The dictated text now has a typeface of its own, so a result reads as writing rather than as interface.
• Steadier haptics: a tap when the rewrite lands and when you confirm an edit, and none while you are typing.
• A Mac app, built from the same source, is available from the project's GitHub page.
```

Character count is well inside Apple's 4000. The Mac line is a statement of fact about an
open-source project, not a purchase link — drop it if App Review ever queries it.

## App Privacy (nutrition label)

Answer: **Data Not Collected.**

Rationale, in case App Review asks: Apple's definition of "collected" is data transmitted off
the device in a way that is accessible to the developer or to a third-party partner of the
developer. Utterclip has no server; nothing reaches the developer. When the user chooses the
cloud engine, the transcript goes to an AI provider the *user* selected, under the *user's own*
account and API key, exactly like a mail client sending mail to a server the user configured.
That provider is not the developer's partner and the developer has no access to the data.
Audio never leaves the device. There is no tracking and no third-party SDK that collects
anything (WhisperKit is a local inference library).

If a reviewer disagrees, the fallback label is: **Data Linked to You: none. Data Not Linked to
You: User Content (Audio Data → no; Other User Content → yes), purpose App Functionality**,
with tracking **No**. That is still honest: the text is user content and is used only to
provide the feature.

## App Review notes

```
Utterclip is a dictation utility. Nothing to sign in to; there is no account system.

HOW TO TEST
1. On first launch the app downloads a ~220 MB speech-recognition model from Hugging Face. Please allow a minute on Wi-Fi. A spinner and "Model loads in the background" shows meanwhile; you can already record.
2. Allow microphone access when asked.
3. Tap the mic, speak a sentence, tap again. The transcript appears and is copied to the clipboard (transcription is fully on-device, using OpenAI's Whisper model via the open-source WhisperKit library).
4. The styled rewrite ("Plain" by default; Slack, WhatsApp, Prompt and Email are the other pills) needs a rewrite engine. Either:
   a) On an iPhone with Apple Intelligence enabled (iOS 26): Settings (gear) → Rewrite engine → turn on "Rewrite on device". No key needed, nothing leaves the device.
   b) Paste this test API key in Settings → AI provider API key:  <<< PASTE A LOW-LIMIT TEST KEY HERE, REVOKE AFTER REVIEW >>>
      The provider is detected from the key prefix. The key is stored in the Keychain and sent only to that provider.
5. Tap another style pill (WhatsApp, Prompt, Email, Plain) to re-run the rewrite; each result is copied to the clipboard.

NEW IN 1.1, IF YOU WANT TO SEE IT
- iCloud sync (Settings → iCloud → Sync with iCloud, on by default): History, styles, settings
  and the API key travel between the reviewer's own devices through their own iCloud account.
  There is no developer server in that path. Turning the switch off stops it and re-stores the
  key as device-only. Nothing about this needs a second device to review the app.
- Editing a result in place: tap the rewritten text, the cursor lands where you tapped, and the
  edited text is copied as you type. The checkmark above the keyboard finishes.
- The Action button can start a dictation on iPhone 15 Pro and later:
  Settings → Action Button → Shortcut → Start dictating.

PRIVACY
- Audio is transcribed on-device and deleted after transcription. It is never uploaded.
- The only network requests are the one-time model download and, if the user chose the cloud engine, the rewrite request to the provider whose key they entered. No analytics, no tracking, no developer server. Privacy policy: https://github.com/ralfchille/utterclip-app/blob/main/PRIVACY.md
- The app writes to the pasteboard; it never reads from it, so no paste prompt appears.
- With iCloud sync on, the app writes History, styles, settings and the API key to the user's
  own CloudKit private database and iCloud Keychain. Nothing is sent to the developer, who has
  no server and cannot read any of it.

WIDGETS / CONTROL
- The Home Screen / Lock Screen widget and the Control Center control ("Dictate") deep-link into the app and start a recording. The control requires iOS 18.

The full source code is public under the MIT license: https://github.com/ralfchille/utterclip-app
```

## Screenshots

Required: **6.9-inch iPhone**, 1320 × 2868 px, portrait, up to 10. App Store Connect scales
these to the smaller iPhone sizes automatically. The set in
[`screenshots/`](screenshots/) was captured on the iPhone 17 Pro Max simulator, light mode;
the dictations shown are sample content, not real recordings.

Six of them, in the order they tell the story: idle, recording, the message, the prompt,
history, settings. Retaking them is one command per screen rather than an afternoon —
`SIMCTL_CHILD_UTTERCLIP_DEMO=idle|recording|slack|prompt|history|settings` puts a Debug build
into that screen at launch, seeding a few past dictations for History and a waveform for the
recording screen, which a simulator has no microphone to produce. Two traps: `simctl` reports
a screenshot as written even when the simulator daemon cannot write to the destination (aim
somewhere under `/tmp` and copy the files in), and a stale system alert survives app
relaunches, so `simctl erase` the device before a run.

Suggested order and caption (if you add caption frames later):

1. `01-idle.png` — "Tap the mic, speak, tap again."
2. `02-result-slack.png` — "Rewritten as a Slack message. Already copied."
3. `03-result-prompt.png` — "Or as a structured prompt for an AI assistant."
4. `04-history.png` — "Every dictation, one tap away."
5. `05-settings.png` — "Your key, your engine, your styles."

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is already in the Info.plist (the app uses only
HTTPS, which is exempt), so App Store Connect will not ask on each upload.
