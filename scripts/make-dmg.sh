#!/bin/bash
#
# Packs the notarised Mac app into a disk image with the usual drag-onto-Applications
# window, then signs, notarises and staples the image itself.
#
# The image needs its own notarisation even though the app inside it is already stapled:
# Gatekeeper judges what was downloaded, and what the user downloads is the .dmg. An
# unsigned image warns on mount, whatever is inside it.
#
# Takes the app from scripts/release-mac.sh's export and leaves build/mac-release/Utterclip.dmg.
# The name carries no version on purpose, so that
# https://github.com/ralfchille/utterclip-app/releases/latest/download/Utterclip.dmg is a
# link the website can keep.
#
# Usage:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-… scripts/make-dmg.sh
#   NOTARY_PROFILE=utterclip-notary scripts/make-dmg.sh
#   SKIP_NOTARIZE=1 scripts/make-dmg.sh      # build and sign only, to look at the window

set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
out="$root/build/mac-release"
app="$out/export/Utterclip.app"
staging="$out/dmg-staging"
rw="$out/Utterclip-rw.dmg"
dmg="$out/Utterclip.dmg"
volume="Utterclip"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

[[ -d "$app" ]] || die "No app at $app. Run scripts/release-mac.sh first."
# Only ever wrap an app that is already through the notary: the image inherits nothing, and
# an unstapled app inside a stapled image still fails on a machine that is offline.
xcrun stapler validate "$app" >/dev/null 2>&1 \
    || die "The app at $app has no notarisation ticket stapled to it.
Run: STAPLE_ONLY=1 ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/release-mac.sh"

notary_args=()
if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    if [[ -n "${ASC_KEY_ID:-}" ]]; then
        key="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
        [[ -f "$key" ]] || die "No API key at $key"
        [[ -n "${ASC_ISSUER_ID:-}" ]] || die "ASC_ISSUER_ID is not set"
        notary_args=(--key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
        notary_args=(--keychain-profile "$NOTARY_PROFILE")
    else
        die "Set ASC_KEY_ID and ASC_ISSUER_ID (or NOTARY_PROFILE, or SKIP_NOTARIZE=1)."
    fi
fi

step "Staging the image's contents"
# Anything left mounted from a previous run would be copied into this one.
hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
rm -rf "$staging" "$rw" "$dmg"
mkdir -p "$staging"
# -R keeps the signature intact; cp without it would flatten the bundle's symlinks.
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

step "Creating a writable image"
# Sized from the contents with room for the filesystem's own overhead.
size=$(( $(du -sm "$staging" | cut -f1) + 40 ))
hdiutil create -srcfolder "$staging" -volname "$volume" -fs HFS+ \
    -format UDRW -size "${size}m" "$rw" -quiet

step "Arranging the window"
mount_output=$(hdiutil attach "$rw" -readwrite -noverify -noautoopen)
device=$(awk 'NR==1{print $1}' <<<"$mount_output")
# Finder does the arranging, and it may not be reachable (no session, automation refused).
# A plain image still installs perfectly, so a failure here is worth a line, not a stop.
if osascript <<'APPLESCRIPT' >/dev/null 2>&1
tell application "Finder"
    tell disk "Utterclip"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 800, 540}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set position of item "Utterclip.app" of container window to {150, 195}
        set position of item "Applications" of container window to {450, 195}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
then
    echo "    Finder arranged the icons."
else
    echo "    Finder would not arrange the icons; the image gets the default layout."
fi
# Mounting leaves this behind, and it would be shipped inside the image.
rm -rf "/Volumes/$volume/.fseventsd"
sync
hdiutil detach "$device" -quiet

step "Compressing"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" -quiet
rm -f "$rw"
rm -rf "$staging"

step "Signing the image"
codesign --sign "Developer ID Application" --timestamp "$dmg"
signature=$(codesign -dv --verbose=4 "$dmg" 2>&1)
grep -q 'Developer ID Application' <<<"$signature" || die "The image is not Developer ID signed."
grep -E 'Authority|Timestamp' <<<"$signature" | sed 's/^/    /'

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
    printf '\nSKIP_NOTARIZE: %s is signed but not notarised. It will warn on a downloaded copy.\n' "$dmg"
    exit 0
fi

step "Notarising the image (this is a second trip through the notary)"
if ! xcrun stapler staple "$dmg" 2>/dev/null; then
    xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait
    xcrun stapler staple "$dmg"
fi
xcrun stapler validate "$dmg"

step "What Gatekeeper sees"
spctl -a -vvv -t open --context context:primary-signature "$dmg" 2>&1 | sed 's/^/    /'

printf '\n\033[1m%s is ready.\033[0m  %s\n' "$(basename "$dmg")" "$(du -h "$dmg" | cut -f1)"
