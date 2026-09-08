# Utterclip Privacy Policy

**Effective date:** 8 September 2026
**Applies to:** the Utterclip iOS app, version 1.0 and later, as distributed on the App Store
and as built from this repository.

Utterclip is a dictation app: it records your voice, transcribes it on your iPhone, and
rewrites the text in a style you choose. It is built so that the app's developer never
receives any of your data. This document explains exactly what the app does with data,
where it goes, and what stays on your phone.

## The short version

- **The developer collects nothing.** No account, no analytics, no crash-reporting SDK, no
  advertising, no server. There is nothing for the developer to receive, sell or share.
- **Your voice never leaves your phone.** Transcription runs on the device. The recording
  is deleted as soon as it has been transcribed.
- **Text leaves your phone only if you choose the cloud rewrite engine**, and then only to
  the AI provider whose API key you entered, under that provider's privacy policy.
- **With the on-device rewrite engine, nothing leaves your phone at all.**
- The App Store privacy label for Utterclip is **Data Not Collected**.

## What the app processes, and where

### Audio

Tapping the mic records audio through the microphone into a temporary file on the device.
When you stop (or the app stops after five seconds of silence), the file is transcribed by
the Whisper speech-recognition model running locally on your iPhone, then deleted. If you
cancel a recording, the file is deleted without being transcribed. Audio is never uploaded,
stored beyond that moment, or accessible to anyone.

The microphone is used only while you are recording. iOS asks for your permission the first
time, and you can revoke it at any time in **Settings → Privacy & Security → Microphone**.

### Transcripts and rewrites

The transcript and every rewritten version of it are:

- placed on the iOS clipboard so you can paste them into another app;
- shown on screen;
- saved to the app's **History**, a file stored in the app's private container on your phone.

History keeps at most 200 entries. You can delete individual entries by swiping, delete all
of them with **Clear** on the History screen, or delete everything by uninstalling the app.

The clipboard is managed by iOS. Anything you copy can be read by apps you paste into and,
if you have Universal Clipboard enabled, is shared with your other Apple devices through
Apple's Handoff mechanism under Apple's terms.

### Rewrite engines

Utterclip offers two ways to rewrite a transcript. You pick one in Settings; the app never
switches on its own.

**On device (Apple Intelligence).** Uses Apple's Foundation Models framework on iOS 26. The
model runs entirely on your iPhone. No text leaves the device. Requires an iPhone that
supports Apple Intelligence.

**Cloud (your own API key).** Sends the transcript, together with the style instructions, to
one of these providers over an encrypted (HTTPS) connection, using the API key you entered:

| Provider | Endpoint | Privacy policy |
|---|---|---|
| Anthropic | `api.anthropic.com` | [anthropic.com/privacy](https://www.anthropic.com/privacy) |
| OpenAI | `api.openai.com` | [openai.com/policies/privacy-policy](https://openai.com/policies/privacy-policy) |
| Google Gemini | `generativelanguage.googleapis.com` | [policies.google.com/privacy](https://policies.google.com/privacy) |
| Groq | `api.groq.com` | [groq.com/privacy-policy](https://groq.com/privacy-policy/) |

Which provider receives your text is determined solely by the key you entered. The request
contains the transcript text, the rewrite instructions, and your API key in a request header.
It contains no device identifier, account identifier, location, or any other information
about you or your phone. Once the text reaches the provider it is governed by that
provider's terms and privacy policy, and by the settings of your account with them (for
example, whether they retain API inputs). Utterclip has no influence over and no visibility
into that.

Cloud rewrites are optional. Without a key, and with the on-device engine off, the app still
transcribes and copies the raw text; only the styled rewrite is skipped.

### Privacy redaction

When the cloud engine is used and **Redact personal details** is on (it is on by default),
the app scans the transcript before sending it and replaces email addresses, phone numbers,
web links and postal addresses with placeholders such as `⟦EMAIL_1⟧`. The provider receives
only the placeholders. When the rewritten text comes back, the original details are put back
in on your phone. Detection uses Apple's built-in text recognition (`NSDataDetector`) and is
not perfect; unusual formats can slip through. Names and other personal details are not
redacted, because detecting them reliably is not possible and they carry the meaning and tone
of a message.

Redaction has no effect on the on-device engine, since nothing is sent anywhere.

### Your API key

The key is stored in the iOS Keychain with the strictest common protection class
(accessible only after the device has been unlocked once, and marked "this device only",
so it is **not** included in iCloud or computer backups and does not sync to other devices).
It is sent only to the provider it belongs to, as described above. Deleting the key in
Settings removes it from the Keychain; uninstalling the app does too.

### The speech-recognition model

On first launch the app downloads the Whisper `small` model (about 220 MB) from
**Hugging Face** (`huggingface.co`), where the model's maintainer, Argmax, publishes it.
That download is a plain file fetch. It does not send any information about you beyond what
any HTTPS request carries (your IP address and a generic user agent). Hugging Face's
handling of that request is described in their
[privacy policy](https://huggingface.co/privacy). The model is cached in the app's
container and reused; it is not downloaded again unless the cache is deleted. The cache is
excluded from iCloud and computer backups, since it can always be downloaded again.

### Settings and styles

Your preferences (default style, copy mode, redaction and engine toggles) and any rewrite
styles you edit or create are stored in the app's local preferences on the device. Style
prompts you write are only ever sent to a cloud provider as part of a rewrite request, in the
same way as the built-in ones.

## Network connections, complete list

Utterclip connects to exactly these hosts, and to nothing else:

1. `huggingface.co` — once, to download the speech model.
2. The API host of the one provider whose key you entered — for each cloud rewrite.

There is no connection to any server operated by the developer, and no connection at all in
the on-device configuration once the model is downloaded.

## What the developer receives

Nothing from the app. The only way information about your use of Utterclip can reach the
developer is through channels you control:

- **Apple** may share aggregated App Store statistics and, if you have opted in to share
  analytics with app developers in iOS Settings, anonymised crash reports. These are handled
  by Apple under [Apple's privacy policy](https://www.apple.com/legal/privacy/).
- **You**, if you contact the developer or open a GitHub issue. Please do not include
  transcripts containing other people's personal information when reporting a bug.

## Backups

Your History and preferences are part of your normal iPhone backup (iCloud Backup or a
computer backup), protected by Apple's backup encryption and your Apple Account. Your API key
and the downloaded speech model are excluded from backups by design.

## Children

Utterclip is a general-purpose utility and is not directed at children under 13 (or the
equivalent minimum age in your region). It collects no data from anyone, of any age.

## Your rights

Because the developer holds no personal data about you, there is nothing for the developer
to access, correct, export or delete on your behalf: everything the app stores is on your
phone and under your control, and everything it sends goes to a provider you chose under an
account you hold. To exercise rights over text you sent to a cloud provider, contact that
provider. To remove everything Utterclip stores, delete the app.

If you are in the European Economic Area, the United Kingdom or Switzerland: the developer
does not act as a controller or processor of your personal data, since none is received.
Where you use a cloud provider, you are the customer of that provider under your own
agreement with them.

## Open source

Utterclip's complete source code is public at
[github.com/ralfchille/utterclip-app](https://github.com/ralfchille/utterclip-app), so every
statement in this policy can be checked against the code. Builds installed from the App
Store are made from that code.

## Changes to this policy

If the app's data handling ever changes (for example, a new engine or a new network
connection), this document will be updated first and the effective date at the top will
change. The version history is in the repository's commit log.

## Contact

<!-- TODO: fill in before submitting the App Store listing -->
Ralf Chille · _[TBD: contact email]_ ·
[GitHub Issues](https://github.com/ralfchille/utterclip-app/issues)
