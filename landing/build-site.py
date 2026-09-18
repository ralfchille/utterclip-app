"""HISTORICAL: this built site/classic/index.html from Main.dc.html, and no longer reproduces it.

The classic design was the front page until the minimal one replaced it on 2026-09-16; it now
lives at site/classic/ and has been edited by hand since this script last ran. Running it would
revert, at least: the images' ../ paths (the page moved into a subdirectory), Schibsted Grotesk
as the body face, the h1 clamp that keeps "Speak the message." on one line on a narrow phone,
and the line naming French among the tested languages. It also serialises SVG differently from
whatever wrote the live page, so even the unchanged parts would churn.

Kept because it documents how the artboard became a page — the class-for-inline-style rewrite
below is the interesting part — and because Main.dc.html is still the design record. If the
classic page ever needs rebuilding, reconcile those differences first. It takes an explicit
output path and has no default, so it cannot overwrite anything by being run without thinking:

    python3 landing/build-site.py /tmp/classic-rebuild.html

The live page to maintain is site/index.html, and build-minimal.py does reproduce that one
byte for byte.
"""
import pathlib, re, sys
if len(sys.argv) < 2:
    sys.exit(__doc__)
here = pathlib.Path(__file__).parent
src = (here / 'Main.dc.html').read_text()
out = pathlib.Path(sys.argv[1])
body = re.search(r'</helmet>(.*?)</x-dc>', src, re.S).group(1).strip()

# Tag the structural containers so the stylesheet can address them by name instead of by
# guessing at inline-style substrings.
TAGS = [
 ('<div style="width:1440px; background:#FBFBFA; padding:0 0 0 0;">', '<div class="page">'),
 ('<div style="display:flex; align-items:center; gap:24px; padding:28px 96px; border-bottom:1px solid #E4E4E1;">',
  '<div class="nav sec">'),
 ('<div style="display:flex; gap:24px; padding:104px 96px 0;">', '<div class="hero sec">'),
 ('<div style="width:700px;">', '<div class="hero-copy">'),
 ('<div style="width:524px; display:flex; align-items:flex-start; justify-content:flex-end; gap:0;">',
  '<div class="hero-art">'),
 ('<div style="border-top:1px solid #E4E4E1; padding-top:56px; display:flex; gap:24px;">', '<div class="split rule">'),
 ('<div style="display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:24px;">', '<div class="g3">'),
 ('<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:0; margin-top:36px;">', '<div class="cases">'),
 ('<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:24px; margin-top:24px;">', '<div class="g2">'),
 ('<div style="display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:24px; margin-top:72px;">', '<div class="g2 g2-lead">'),
 ('<div style="display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:24px; margin-top:88px; border-top:1px solid #2A2A2A; padding-top:40px;">',
  '<div class="g3 g3-dev">'),
 ('<div style="margin-top:56px; display:flex; align-items:center; gap:40px;">', '<div class="syncs">'),
 ('<div style="display:flex; gap:24px;">', '<div class="split">'),
 ('<div style="width:390px;">', '<div class="col-a">'),
 ('<div style="width:722px;">', '<div class="col-b">'),
 ('<div style="width:722px; border:1px solid #E4E4E1; background:#FFFFFF; padding:40px;">', '<div class="col-b card">'),
]
for old, new in TAGS:
    n = body.count(old)
    if n == 0:
        print('  ! not found:', old[:64], file=sys.stderr)
    body = body.replace(old, new)

body = body.replace('<div style="display:flex; align-items:flex-end; gap:28px;">', '<div class="device">')
body = body.replace('<div style="padding:132px 96px 112px; text-align:center;">',
                    '<div class="sec close" style="padding-top:132px; padding-bottom:112px;">')
body = body.replace('<div style="display:flex; align-items:center; justify-content:center; gap:20px; margin-top:44px;">',
                    '<div class="cta">')
body = body.replace('<div style="display:flex; align-items:center; gap:20px; margin-top:44px;">',
                    '<div class="cta-hero">')
# the hero deck was a hard 560; it has to give way before the side padding does
body = body.replace('width:560px; font-size:21px', 'max-width:560px; font-size:21px')
body = re.sub(r'<div style="display:grid; grid-template-columns:repeat\(4, minmax\(0, 1fr\)\); gap:24px; padding:16px 0; border-top:1px solid #E4E4E1;([^"]*)">',
              r'<div class="spec" style="border-top:1px solid #E4E4E1;\1">', body)
body = body.replace('style="grid-column:span 3;"', 'class="spec-v"')
# section padding: one class, one value to change per breakpoint
body = re.sub(r'style="padding:(\d+)px 96px( 0| 112px| 104px)?;"', r'class="sec" style="padding-top:\1px; padding-bottom:\2;"', body)
body = body.replace('padding-bottom:;', 'padding-bottom:0;').replace('padding-bottom: 0;', 'padding-bottom:0;')
body = body.replace('padding-bottom: 112px;', 'padding-bottom:112px;').replace('padding-bottom: 104px;', 'padding-bottom:104px;')
body = body.replace('<div id="devices" style="margin-top:132px; background:#0B0B0B; color:#FBFBFA; padding:96px 96px 104px;">',
                    '<div id="devices" class="sec dark" style="margin-top:132px; padding-top:96px; padding-bottom:104px;">')
body = body.replace('<div style="border-top:1px solid #E4E4E1; padding:32px 96px; display:flex; align-items:center; gap:24px;">',
                    '<div class="nav foot sec" style="border-top:1px solid #E4E4E1; padding-top:32px !important; padding-bottom:32px !important;">')

CSS = '''
  body { margin:0; font-family:Inter,"Helvetica Neue",Arial,sans-serif; -webkit-font-smoothing:antialiased;
         color:#0B0B0B; background:#FBFBFA; }
  a { color:#0B0B0B; } a:hover { color:#6B6B6B; }
  img, svg { max-width:100%; height:auto; }
  .mono { font-family:"JetBrains Mono",ui-monospace,Menlo,monospace; }
  .serif { font-family:"Source Serif 4",Georgia,serif; }
  /* The app's own wordmark, not the page's type: Schibsted Grotesk semibold, title case. */
  .wordmark { font-family:'Schibsted Grotesk',-apple-system,system-ui,sans-serif;
              font-weight:600; letter-spacing:normal; }
  .lbl { font-family:"JetBrains Mono",ui-monospace,Menlo,monospace; font-size:12px;
         letter-spacing:normal; text-transform:uppercase; color:#6B6B6B; }
  .page [style*="letter-spacing:0.12em"], .page [style*="letter-spacing:0.14em"] { letter-spacing:normal !important; }

  .page { width:100%; max-width:1440px; margin:0 auto; background:#FBFBFA; }
  .sec { padding-left:96px; padding-right:96px; }
  .dark { background:#0B0B0B; color:#FBFBFA; }
  .nav { display:flex; align-items:center; gap:26px; padding-top:44px; padding-bottom:30px; }   /* a page header needs more air than an artboard edge */
  .nav a { font-size:15px !important; text-decoration:none; }   /* beats the inline 13px */
  .hero { display:flex; gap:24px; padding-top:104px; }   /* the artboard's value; the class rewrite had dropped it */
  .hero-copy { width:700px; }
  .hero-art { width:524px; display:flex; align-items:flex-start; justify-content:flex-end; }
  .split { display:flex; gap:24px; }
  .split.rule { border-top:1px solid #E4E4E1; padding-top:56px; }
  .col-a { width:390px; } .col-b { width:722px; }
  .card { border:1px solid #E4E4E1; background:#FFFFFF; padding:40px; }
  .g2 { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:24px; margin-top:24px; }
  .g2-lead { margin-top:72px; }
  .g3 { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:24px; }
  .g3-dev { margin-top:88px; border-top:1px solid #2A2A2A; padding-top:40px; }
  .cases { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); margin-top:36px; }
  .device { display:flex; align-items:flex-end; gap:28px; }
  .syncs { margin-top:56px; display:flex; align-items:center; gap:40px; }
  .spec { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:24px; padding:16px 0; }
  .spec-v { grid-column:span 3; }
  .close { text-align:center; }
  .cta { display:flex; align-items:center; justify-content:center; gap:20px; margin-top:44px; }
  .cta-hero { display:flex; align-items:center; gap:20px; margin-top:44px; }

  @media (max-width:1140px) {
    .sec { padding-left:48px; padding-right:48px; }
    .hero-copy, .hero-art, .col-a, .col-b { width:auto; }
    .hero-copy { flex:1 1 430px; } .hero-art { flex:0 1 460px; }
    .col-a { flex:1 1 280px; } .col-b { flex:2 1 400px; }
    .page h1 { font-size:58px !important; }
  }
  @media (max-width:880px) {
    .hero { padding-top:72px; }
    .hero, .split, .syncs, .device { flex-direction:column; align-items:flex-start; }
    .hero-art { justify-content:flex-start; }
    .g2, .g3, .cases, .spec { grid-template-columns:minmax(0,1fr); }
    .spec { gap:4px; } .spec-v { grid-column:auto; }
    .cases > div { padding:26px 0 !important; border-left:0 !important;
                   border-bottom:1px solid #E4E4E1 !important; }
    .device > div { padding-bottom:0 !important; }
    .page h1 { font-size:46px !important; line-height:1.0 !important; }
    .page h2 { font-size:30px !important; }
    .page img[style*="margin-right:-52px"] { margin-right:-32px !important; }
    .page img[style*="margin-top:132px"] { margin-top:64px !important; }
  }
  @media (max-width:620px) {
    .sec { padding-left:24px; padding-right:24px; }
    .nav { flex-wrap:wrap; gap:14px; padding-top:32px !important; padding-bottom:24px !important; }
    .hero { padding-top:52px; }
    /* the closing block is centred, so it can use the full width */
    .close { padding-left:0 !important; padding-right:0 !important; }
    .cta { flex-direction:column; gap:18px; }
    .cta-hero { flex-direction:column; align-items:flex-start; gap:16px; }
    .cta a, .cta-hero a { white-space:nowrap; }
    .card, .page [style*="padding:32px 40px"] { padding:24px !important; }
    .page h1 { font-size:38px !important; }
    .page h2 { font-size:25px !important; }
    .page [style*="font-size:64px"] { font-size:32px !important; }
    .page [style*="font-size:21px"] { font-size:18px !important; }
    .page [style*="font-size:22px"] { font-size:18px !important; }
    /* One device in the hero on a phone; the Mac gets its own section further down. */
    .hero-art { align-self:center; }
    .page img[style*="margin-right:-52px"] { margin-right:0 !important; width:240px !important; }
    .page img[style*="margin-top:132px"] { display:none !important; }
    /* The in-page links are noise at this width; Source is the one worth keeping. */
    .nav a[href^="#"] { display:none !important; }
  }
'''

HEAD = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Utterclip — speak the message, paste the message</title>
<meta name="description" content="Dictate on iPhone or Mac. Utterclip transcribes on the device, rewrites what you said as the message you were about to type — to a colleague or to an assistant — and leaves it on your clipboard.">
<link rel="icon" href="icon.png">
<meta property="og:title" content="Utterclip — speak the message, paste the message">
<meta property="og:description" content="Dictation for iPhone and Mac. Transcribed on the device, rewritten as the message you meant to send, left on your clipboard.">
<meta property="og:image" content="https://ralfchille.github.io/utterclip-app/mac.png">
<meta property="og:url" content="https://ralfchille.github.io/utterclip-app/">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Schibsted+Grotesk:wght@600&family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;1,8..60,400&display=swap">
<style>''' + CSS + '''</style>
</head>
<body>
'''
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(HEAD + body + '\n</body>\n</html>\n')
print('wrote', out)
