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
#   · an App Store Connect API key, used both to create the Developer ID provisioning
#     profile and to talk to the notary service:
#       ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# Usage:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-… scripts/release-mac.sh
#
# Instead of the key, an app-specific password stored with
# `xcrun notarytool store-credentials` can carry the notarisation half:
#   NOTARY_PROFILE=utterclip-notary scripts/release-mac.sh
# (the provisioning half then needs a Developer ID profile already installed).

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
signing_args=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" ]]; then
    key="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
    [[ -f "$key" ]] || die "No API key at $key"
    [[ -n "${ASC_ISSUER_ID:-}" ]] || die "ASC_ISSUER_ID is not set"
    notary_args=(--key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    signing_args+=(-authenticationKeyPath "$key"
                   -authenticationKeyID "$ASC_KEY_ID"
                   -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
else
    die "Set ASC_KEY_ID and ASC_ISSUER_ID (or NOTARY_PROFILE). See the header of this script."
fi

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || die "No Developer ID Application certificate in the keychain.
Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."

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
    "${signing_args[@]}" \
    | tail -20

step "Exporting with the Developer ID certificate"
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist \
    "${signing_args[@]}" \
    | tail -20
[[ -d "$app" ]] || die "Export produced no app at $app"

step "Checking the signature before it goes to the notary"
codesign -dv --verbose=4 "$app" 2>&1 | grep -E 'Authority|flags|Identifier' || true
codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime' \
    || die "The export is not signed with the hardened runtime; the notary will refuse it."
codesign -dv "$app" 2>&1 | grep -q 'Developer ID Application' \
    || die "The export is not signed with a Developer ID certificate."
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
