"""Draws the backdrop for the disk image window, at 1x and 2x, into scripts/dmg-background.tiff.

Run it when the wording or the window size changes; make-dmg.sh uses the committed .tiff so
that building a release needs nothing but Xcode and the notary.

    python3 scripts/make-dmg-background.py

The arrow earns its place: macOS 26 draws the Applications alias in a disk image as an empty
dashed square (a Finder bug, fixed around 26.4), and a window whose right-hand target is
invisible reads as broken. The arrow and the line beneath say where the app goes whether or
not Finder finds the folder's icon.
"""
import pathlib, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

W, H = 600, 400            # the window's content area, matching the bounds make-dmg.sh sets
ICON_Y = 195               # both icons' centre line, matching the positions it sets
APP_X, DEST_X = 150, 450

PAPER, MUTE, RULE = "#FBFBFA", "#6B6B6B", "#D6D6D2"
FONT = pathlib.Path(__file__).parent.parent / "Utterclip/Resources/Fonts/SchibstedGrotesk[wght].ttf"


def draw(scale: int) -> Image.Image:
    im = Image.new("RGB", (W * scale, H * scale), PAPER)
    d = ImageDraw.Draw(im)
    s = lambda v: v * scale

    # The arrow lives in the gap between the two icons, clear of both.
    x0, x1, y = s(258), s(342), s(ICON_Y)
    d.line([(x0, y), (x1 - s(7), y)], fill=RULE, width=max(1, s(2)))
    head = s(9)
    d.polygon([(x1, y), (x1 - head, y - head * 0.62), (x1 - head, y + head * 0.62)], fill=RULE)

    try:
        font = ImageFont.truetype(str(FONT), s(15))
        font.set_variation_by_axes([500])
    except Exception:
        font = ImageFont.load_default(s(15))
    caption = "Drag Utterclip into your Applications folder"
    box = d.textbbox((0, 0), caption, font=font)
    d.text(((im.width - (box[2] - box[0])) / 2, s(322)), caption, font=font, fill=MUTE)
    return im


out = pathlib.Path(__file__).parent / "dmg-background.tiff"
tmp = [out.with_suffix(f".{n}x.png") for n in (1, 2)]
for path, scale in zip(tmp, (1, 2)):
    draw(scale).save(path)
# One file carrying both sizes, so the window is sharp on a Retina display and right on a
# display that is not.
subprocess.run(["tiffutil", "-cathidpicheck", *map(str, tmp), "-out", str(out)], check=True)
for path in tmp:
    path.unlink()
print("wrote", out)
