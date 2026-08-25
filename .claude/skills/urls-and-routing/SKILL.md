---
name: urls-and-routing
description: How a request reaches this VM — the hostname scheme, which subdomains map where, tailnet vs public exposure, and why TLS is not handled in here. Use when asked about URLs, domains, subdomains, certificates, or why something is or is not reachable.
---

# How URLs reach this VM

## The scheme

    https://<project>.appsmoothly.com             -> port 80    (Campfire)
    https://app.<project>.appsmoothly.com         -> port 3000  (your app)
    https://<anything>.<project>.appsmoothly.com  -> port 80    (wildcard -> Campfire)

`app.` is matched more specifically than the wildcard, so it wins. Any other
subdomain currently lands on Campfire.

## The path a request takes

**Public projects:**

    browser -> VPS :443            TCP forwarded by SNI. No TLS termination,
                                   no HTTP parsing. It cannot read the traffic.
            -> tunnel              to the desktop
            -> Caddy               terminates TLS, checks login, proxies
            -> this VM :80 / :3000

**Tailnet-only projects** skip the VPS: the browser reaches the desktop directly
over the private network, and the URL carries an explicit `:8443`.

## What this means for you

* **You never handle TLS.** Certificates are obtained and renewed outside this
  VM by DNS-01. There is nothing to install in here, and you should not run
  certbot or ask Caddy for automatic HTTPS.
* **You only ever see plain HTTP** arriving on `80` and `3000`.
* **The client IP you see is the proxy**, not the visitor. Use
  `X-Forwarded-For` if you need the real one.
* **Adding a new hostname needs a change outside this VM** — a DNS record and a
  proxy route. You cannot do it from in here. Ask the human. What you *can* do
  is route hostnames that already point here, with a local Caddy.

## Exposure modes

| | tailnet-only | public |
|---|---|---|
| Who can reach it | the owner's own devices | anyone |
| Login | none — the tunnel is the auth | tinyauth (username + password) |
| URL | `https://<project>.appsmoothly.com:8443` | `https://<project>.appsmoothly.com` |

Which mode this VM is in was decided when it was created and cannot be changed
from inside. If you are unsure, ask — it matters a great deal before you put
anything sensitive on a page.

## Checking

    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:80/     # campfire
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/   # your app

If those work but the public URL does not, the problem is outside this VM and
you should say so rather than changing things in here.
