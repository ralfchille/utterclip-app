# What I Need From You to Get v1 Done

Companion to `voice-app-implementation-plan.md`. These are the decisions, assets, and access
required before (and during) the build. Grouped by when they're needed. Nothing here is huge —
most are one-line answers.

---

## Blockers — needed before coding starts

1. **Apple developer setup.**
   - A Mac with **Xcode 15+** installed.
   - An **Apple ID / Apple Developer account** to run on a physical device (free account works
     for personal device testing; paid $99/yr only needed for TestFlight/App Store).
   - Confirm you'll test on a **real iPhone** (which model?) — Whisper timing must be checked on
     device, not the simulator.

2. **Anthropic API key** (for the cloud rewriter). ✅ You have one.
   - ⚠️ **Security:** a key was pasted into chat and should be **revoked and regenerated** — never
     store a key in a doc, source file, or chat. It is NOT written anywhere in these files.
   - Handling: enter the (new) key **once into the device Keychain at dev time**; the app reads it
     via `KeyProvider`. For v1 this is your key. (User-supplied keys are future work.)
   - Rough cost: rewriting is short text, so pennies per use.

3. **Rewrite model choice.** ✅ **`claude-haiku-4-5`** (fast, low cost).

4. **Whisper model delivery** ✅ **A) Download on first launch** (cached afterward).

---

## Confirmations — RESOLVED ✅

5. **Minimum iOS version:** ✅ **iOS 17**.

6. **Languages:** ✅ **German + English** (multilingual `small` handles it; used for testing).

7. **Default style** for the one-tap flow: ✅ **Slack to colleagues** (changeable in Settings later).

8. **Style wording:** ✅ Use the five prompts in Appendix A **as-is** for v1 — no tone changes.

---

## Nice-to-have — improves quality, not blocking

9. **The reference video.** You mentioned reproducing "what you see in the video." If you can
   share it (or a link/description), I'll match the exact record/stop UX and any details I'm
   currently guessing at.

10. **Personal voice sample.** If you want the rewrites to "sound like you," a few examples of
    real messages you've sent (one Slack, one WhatsApp, one email) let me tune the prompts to your
    style instead of generic defaults.

11. **App name & icon.** ✅ Name: **Voicer**. Icon: ✅ **use a placeholder for v1** (simple
    monochrome mic glyph); real icon later.

12. **Branding/design system.** ✅ Private app, **no external design system.** Minimal black &
    white, Apple HIG, **Liquid Glass on iOS 26+ with graceful fallback to standard materials on
    iOS 17–25** (details in plan §1a).

---

## What I do NOT need from you

- Any server/backend — v1 is fully client-side (local Whisper + direct API call).
- Provisioning profiles / certificates for distribution — only relevant if/when you want
  TestFlight.
- The on-device MLX rewriter — deferred to future work by design.

---

## Fastest path to unblock me

The absolute minimum to start building end-to-end: **items 1, 2, 3, 4** (dev setup, API key,
rewrite model, model delivery). Everything else can be answered while I build, or defaulted and
adjusted later.
