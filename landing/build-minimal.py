"""site/index.html is derived from Minimal.dc.html: the artboard is the single source.

    python3 landing/build-minimal.py site/index.html

Run it from anywhere; the artboard is found beside this file.
"""
import pathlib, re, sys
src = pathlib.Path(__file__).with_name('Minimal.dc.html').read_text()
out = pathlib.Path(sys.argv[1])
t = src.replace('<script src="./support.js"></script>\n', '')            # the canvas editor's runtime, not the site's
# the page lives at the site root, beside icon.png
meta = '''<meta name="description" content="Dictate on iPhone or Mac. Utterclip transcribes on the device, rewrites what you said as the message you were about to type — to a colleague or to an assistant — and leaves it on your clipboard.">
<link rel="icon" href="icon.png">
<meta property="og:title" content="Utterclip — Speak the message. Paste the message.">
<meta property="og:description" content="Dictation for iPhone and Mac. Transcribed on the device, rewritten as the message you meant to send, left on your clipboard.">
<meta property="og:image" content="https://ralfchille.github.io/utterclip-app/mac.png">
<meta property="og:url" content="https://ralfchille.github.io/utterclip-app/">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">
'''
t = t.replace('<link rel="preconnect" href="https://fonts.googleapis.com">', meta + '<link rel="preconnect" href="https://fonts.googleapis.com">', 1)
assert 'support.js' not in t
out.parent.mkdir(parents=True, exist_ok=True); out.write_text(t)
print('wrote', out, len(t), 'bytes')
