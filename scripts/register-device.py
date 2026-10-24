#!/usr/bin/python3 -I
"""Registers a phone on the developer account (App Store Connect API key), so Xcode can put it
in a development profile and install onto it. Does nothing if it's already registered.

  scripts/register-device.py UDID NAME
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error


def token():
    """A short-lived App Store Connect token from ~/.appstoreconnect (as testflight-status.py)."""
    values = dict(line.strip().split("=", 1) for line in open(os.path.expanduser("~/.appstoreconnect/config")) if "=" in line)
    kid, issuer = values["KEY_ID"], values["ISSUER_ID"]
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


def call(method, path, body=None):
    request = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                     data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def main():
    udid, name = sys.argv[1], sys.argv[2]
    found = call("GET", f"/v1/devices?filter[udid]={udid}")["data"]
    if found:
        print(f"{name} is already registered ({found[0]['attributes']['status'].lower()}).")
        return
    try:
        call("POST", "/v1/devices", {"data": {"type": "devices", "attributes": {"name": name, "udid": udid, "platform": "IOS"}}})
    except urllib.error.HTTPError as error:
        sys.exit(f"Couldn't register {name}: {error.read().decode()[:300]}")
    print(f"Registered {name} on the developer account.")


main()
