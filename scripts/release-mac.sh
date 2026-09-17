#!/bin/bash
#
# Builds the Mac app for direct distribution: archive, re-sign with the Developer ID
# certificate, notarise, staple, and leave a zip ready to attach to a GitHub release.
#
# The Mac app does not go to the Mac App Store — it is unsandboxed so that the global
# shortcut can read the caret position and paste back into other apps, and the store
# requires the sandbox. See plan/1.1-release-checklist.md.
#
# What it needs once, outside this repo:
#   · a Developer ID Application certificate in the login keychain
#     (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application)
#   · a Developer ID provisioning profile named "Utterclip Mac Developer ID", made at
#     developer.apple.com and installed by double-clicking it. Made by hand on purpose:
#     letting Xcode create it ("cloud signing") needs an App Store Connect key with Admin
#     access, which is a much more powerful credential to leave on disk than this needs.
#   · an App Store Connect API key with App Manager access, for the notary service:
#       ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# Usage:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-… scripts/release-mac.sh
#
# An app-specific password stored with `xcrun notarytool store-credentials` works just as
# well as the key:
#   NOTARY_PROFILE=utterclip-notary scripts/release-mac.sh

set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
out="$root/build/mac-release"
archive="$out/Utterclip.xcarchive"
export_dir="$out/export"
app="$export_dir/Utterclip.app"

version=$(awk -F'"' '/"MARKETING_VERSION"/ {print $4; exit}' Project.swift)
build=$(awk -F'"' '/"CURRENT_PROJECT_VERSION"/ {print $4; exit}' Project.swift)
zip="$out/Utterclip-$version.zip"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

# Credentials: either the API key (both halves) or a stored notary profile (one half).
notary_args=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
    key="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
    [[ -f "$key" ]] || die "No API key at $key"
    [[ -n "${ASC_ISSUER_ID:-}" ]] || die "ASC_ISSUER_ID is not set"
    notary_args=(--key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
else
    die "Set ASC_KEY_ID and ASC_ISSUER_ID (or NOTARY_PROFILE). See the header of this script."
fi

# Note on the here-strings below rather than pipes: `set -o pipefail` plus a `grep -q` that
# exits on its first match sends SIGPIPE to whatever is still writing, and the pipeline then
# reports 141 for a check that actually passed.
identities=$(security find-identity -v -p codesigning)
grep -q "Developer ID Application" <<<"$identities" \
    || die "No Developer ID Application certificate in the keychain.
Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."

profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
decoded=$(mktemp -t utterclip-profile)
trap 'rm -f "$decoded"' EXIT
found=no
for p in "$profiles"/*.provisionprofile; do
    [[ -e "$p" ]] || continue
    security cms -D -i "$p" -o "$decoded" 2>/dev/null || continue
    name=$(/usr/libexec/PlistBuddy -c "Print :Name" "$decoded" 2>/dev/null || true)
    [[ "$name" == "Utterclip Mac Developer ID" ]] && found=yes
done
[[ "$found" == yes ]] \
    || die "No provisioning profile named 'Utterclip Mac Developer ID' is installed.
Make one at developer.apple.com → Certificates, Identifiers & Profiles → Profiles → + →
Developer ID, for com.ralfchille.voicer.mac, and double-click the download to install it."

step "Generating the project (Utterclip $version build $build)"
mise exec tuist@4.200.5 -- tuist generate --no-open

step "Archiving"
rm -rf "$out"
mkdir -p "$out"
xcodebuild archive \
    -workspace Utterclip.xcworkspace \
    -scheme UtterclipMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    | tail -20

step "Exporting with the Developer ID certificate"
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist \
    | tail -20
[[ -d "$app" ]] || die "Export produced no app at $app"

step "Checking the signature before it goes to the notary"
signature=$(codesign -dv --verbose=4 "$app" 2>&1)
grep -E 'Authority|flags|Identifier' <<<"$signature" | sed 's/^/    /' || true
grep -q 'flags=.*runtime' <<<"$signature" \
    || die "The export is not signed with the hardened runtime; the notary will refuse it."
grep -q 'Developer ID Application' <<<"$signature" \
    || die "The export is not signed with a Developer ID certificate."
# Universal or not, say so — the notes that go with the download depend on it.
echo "architectures: $(lipo -archs "$app/Contents/MacOS/Utterclip")"
ents="$out/entitlements.plist"
codesign -d --entitlements - --xml "$app" 2>/dev/null > "$ents"
# The push entitlement has to be the production one — a Developer ID app talks to the
# production APNs, and CloudKit's change notifications ride on it.
aps=$(/usr/libexec/PlistBuddy -c "Print :com.apple.developer.aps-environment" "$ents" 2>/dev/null || echo missing)
echo "aps-environment: $aps"
[[ "$aps" == production ]] \
    || die "aps-environment is '$aps', not production: the Mac app would ask the APNs sandbox
for CloudKit's change notifications and never hear about a new dictation from the phone."
# Development builds carry get-task-allow so the debugger can attach. The notary service
# rejects anything that still has it.
/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ents" >/dev/null 2>&1 \
    && die "The export still carries get-task-allow; the notary will refuse it."
# The Developer ID profile has to be in the bundle: without it the iCloud entitlements are
# unbacked and macOS refuses the container on another Mac.
[[ -f "$app/Contents/embedded.provisionprofile" ]] \
    || die "No embedded.provisionprofile in the export: CloudKit would fail on any other Mac."

step "Notarising (a few minutes)"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" "${notary_args[@]}" --wait

step "Stapling"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

step "What Gatekeeper sees"
spctl -a -vvv -t exec "$app" 2>&1 | sed 's/^/    /'

step "Packing the stapled app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

printf '\n\033[1mUtterclip %s (%s) is notarised and stapled.\033[0m\n' "$version" "$build"
printf '  app: %s\n  zip: %s\n' "$app" "$zip"
printf '\nAttach the zip to a GitHub release, and remember that the first launch of a build\n'
printf 'with a new signature needs Utterclip removed from System Settings → Privacy &\n'
printf 'Security → Accessibility and added again.\n'
