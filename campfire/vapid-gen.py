#!/usr/bin/env python3
"""Generate a VAPID keypair (P-256, base64url) using only openssl + stdlib."""
import base64, re, subprocess, sys, tempfile, os
with tempfile.NamedTemporaryFile(suffix=".pem", delete=False) as f:
    pem = f.name
subprocess.run(["openssl","ecparam","-name","prime256v1","-genkey","-noout","-out",pem],check=True)
txt = subprocess.run(["openssl","ec","-in",pem,"-text","-noout"],capture_output=True,text=True,check=True).stderr \
    + subprocess.run(["openssl","ec","-in",pem,"-text","-noout"],capture_output=True,text=True,check=True).stdout
os.unlink(pem)
def grab(label, nxt):
    m = re.search(label + r":\s*\n((?:\s+[0-9a-f:]+\n)+)", txt)
    return bytes.fromhex(re.sub(r"[^0-9a-f]", "", m.group(1)))
priv = grab("priv", None)
pub  = grab("pub", None)
if len(priv) == 33 and priv[0] == 0: priv = priv[1:]   # strip leading zero pad
b64 = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
print("VAPID_PRIVATE_KEY=" + b64(priv))
print("VAPID_PUBLIC_KEY=" + b64(pub))
