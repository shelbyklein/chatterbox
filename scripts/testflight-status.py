#!/usr/bin/python3 -I
"""Where an iPhone build is in TestFlight, from App Store Connect (with the API key that
scripts/testflight.sh uses, in ~/.appstoreconnect/config).

  scripts/testflight-status.py BUILD          e.g. 202610130036: prints "VALID IN_BETA_TESTING"
  scripts/testflight-status.py BUILD --wait   until it's testable, or stuck (Missing Export
                                              Compliance, failed, invalid); exits 1 unless testable
"""
import base64, json, os, subprocess, sys, time, urllib.request

BUNDLE = "com.shelbyklein.Chatterbox.mobile"


def config():
    values = {}
    for line in open(os.path.expanduser("~/.appstoreconnect/config")):
        if "=" in line:
            name, value = line.strip().split("=", 1)
            values[name] = value
    return values["KEY_ID"], values["ISSUER_ID"]


def token():
    kid, issuer = config()
    key = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
    enc = lambda data: base64.urlsafe_b64encode(data).rstrip(b"=")
    now = int(time.time())
    head = enc(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    body = enc(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=head + b"." + body, capture_output=True, check=True).stdout
    # openssl signs in DER; a JWT wants the raw r and s.
    i = 2 if der[1] < 0x80 else 2 + (der[1] - 0x80)
    parts = []
    for _ in range(2):
        length = der[i + 1]
        parts.append(int.from_bytes(der[i + 2:i + 2 + length], "big"))
        i += 2 + length
    return (head + b"." + body + b"." + enc(parts[0].to_bytes(32, "big") + parts[1].to_bytes(32, "big"))).decode()


def get(path):
    request = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def state(build):
    app = get(f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    found = get(f"/v1/builds?filter[app]={app}&filter[version]={build}&include=buildBetaDetail")
    if not found["data"]:
        return "NOT_YET_LISTED"
    beta = [x["attributes"].get("internalBuildState", "") for x in found.get("included", [])]
    return " ".join([found["data"][0]["attributes"]["processingState"]] + beta)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    build, wait = sys.argv[1], "--wait" in sys.argv
    while True:
        try:
            now = state(build)
        except Exception as error:  # a dropped request while waiting is retried
            if not wait:
                sys.exit(f"testflight-status: {error}")
            now = ""
        done = any(word in now for word in ("IN_BETA_TESTING", "READY_FOR_BETA", "MISSING", "FAILED", "INVALID"))
        if not wait or done:
            print(f"build {build}: {now}")
            sys.exit(0 if not wait or "BETA" in now and "MISSING" not in now else 1)
        time.sleep(30)


main()
