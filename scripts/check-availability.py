"""Asks App Store Connect which territories the app is actually selling in, and why not where
it isn't.

    ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-… python3 scripts/check-availability.py

Worth having because the storefronts and the setting disagree in a way that is easy to
misread: a territory can be selected for sale and still not be buyable. On 2026-09-18 every
one of the 27 EU territories came back available=true with the status
TRADER_STATUS_NOT_PROVIDED, while App Store Connect's own Compliance row read "Digital
Services Act · 27 Countries or Regions · In Review". Both were true: the trader details had
been submitted the day before and Apple had not finished verifying them, and until it does the
EU stays withheld. So read this status as "no accepted trader status yet", not as "you forgot
to fill the form" — nothing to do with the app, and not fixed by shipping a new version.
Checking a storefront by hand shows only that Germany is missing; this says what is holding
it.

The same key the release scripts use, with App Manager access, is enough. It is read-only
here, and the key is read from ~/.appstoreconnect/private_keys — never from the repository.
"""
import base64, json, os, subprocess, sys, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

APP_ID = os.environ.get("ASC_APP_ID", "6809807393")          # Utterclip on iOS
EU = {"AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
      "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
      "SVN", "ESP", "SWE"}


def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def token():
    key_id = os.environ.get("ASC_KEY_ID") or die("ASC_KEY_ID is not set. See the header.")
    issuer = os.environ.get("ASC_ISSUER_ID") or die("ASC_ISSUER_ID is not set.")
    path = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(path):
        die(f"No API key at {path}")
    with open(path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
    now = int(time.time())
    signing = (b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode()) + b"."
               + b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 900,
                                 "aud": "appstoreconnect-v1"}).encode()))
    r, s = utils.decode_dss_signature(key.sign(signing, ec.ECDSA(hashes.SHA256())))
    return (signing + b"." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


def get(path, bearer):
    # curl rather than urllib: the system Python here has no CA bundle, and curl uses the
    # keychain's trust store.
    out = subprocess.run(["curl", "-sf", "-H", f"Authorization: Bearer {bearer}",
                          "https://api.appstoreconnect.apple.com" + path],
                         capture_output=True)
    if out.returncode:
        die(f"Request failed: {path}\n{out.stderr.decode()[:400]}")
    return json.loads(out.stdout)


bearer = token()
app = get(f"/v1/apps/{APP_ID}", bearer)["data"]["attributes"]
print(f'{app["name"]}  ({app["bundleId"]}, {APP_ID})\n')

rows = []
for t in get(f"/v2/appAvailabilities/{APP_ID}/territoryAvailabilities?limit=200", bearer)["data"]:
    raw = t["id"] + "=" * (-len(t["id"]) % 4)
    code = json.loads(base64.urlsafe_b64decode(raw))["t"]
    a = t["attributes"]
    rows.append((code, bool(a.get("available")), tuple(a.get("contentStatuses") or ())))

selling = [r for r in rows if r[1] and r[2] == ("AVAILABLE",)]
held = [r for r in rows if r[1] and r[2] != ("AVAILABLE",)]
off = [r for r in rows if not r[1]]
print(f"{len(rows)} territories: {len(selling)} selling, {len(held)} selected but held back, "
      f"{len(off)} not for sale")

if held:
    print("\nSelected for sale, but Apple is withholding them:")
    by_reason = {}
    for code, _, statuses in held:
        by_reason.setdefault(statuses, []).append(code)
    for statuses, codes in sorted(by_reason.items()):
        eu = sorted(c for c in codes if c in EU)
        print(f"  {', '.join(statuses)} — {len(codes)} territories"
              + (f", including all {len(eu)} EU ones" if len(eu) == len(EU) else ""))
        print("    " + " ".join(sorted(codes)))

if off:
    print("\nNot for sale (deliberate, unless it surprises you):")
    for code, _, statuses in sorted(off):
        print(f"  {code} — {', '.join(statuses) or 'no reason given'}")

de = next((r for r in rows if r[0] == "DEU"), None)
print(f"\nGermany: {'selling' if de and de[2] == ('AVAILABLE',) else 'NOT selling'}"
      + (f" — {', '.join(de[2])}" if de and de[2] != ("AVAILABLE",) else ""))
