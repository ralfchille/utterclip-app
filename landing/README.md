# Landing page sources

The site published at <https://ralfchille.github.io/utterclip-app/> is generated from the
artboards here. `site/` holds the built pages and the images; this folder holds what they were
built from, so an edit starts at the source rather than in generated HTML.

The artboards are Claude Design canvas files (`.dc.html`): plain HTML that also opens in the
design canvas described by `canvas.json`. The images are symlinks into `site/`, which keeps one
copy of each binary and lets the artboards find them by the same bare filename the built pages
use.

| Source | Built by | Page |
|---|---|---|
| `Minimal.dc.html` | `build-minimal.py` | `site/index.html` — the front page |
| `Main.dc.html` | `build-site.py` *(historical)* | `site/classic/index.html` |
| `Mobile.dc.html`, `Sketch.dc.html` | — | studies, never published |

## Changing the front page

Edit `Minimal.dc.html`, then:

```sh
python3 landing/build-minimal.py site/index.html
git subtree push --prefix site origin gh-pages
```

The build only strips the canvas editor's runtime and inserts the `<head>` metadata, so the
artboard is genuinely the page. It reproduces the live `site/index.html` byte for byte — worth
checking with a `diff` against a temporary file before publishing anything.

## The classic page

The classic design was the front page until 16 September 2026. It now lives at `site/classic/`
and has been edited by hand since, so `build-site.py` no longer reproduces it and would revert
those edits; its docstring lists what diverged. It takes an explicit output path and refuses to
run without one. Treat the classic page as hand-maintained and `Main.dc.html` as the design
record behind it.
