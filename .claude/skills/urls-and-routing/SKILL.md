---
name: urls-and-routing
description: How a request reaches this VM — the hostname scheme, which subdomains map where, tailnet vs public exposure, and why TLS is not handled in here. Use when asked about URLs, domains, subdomains, certificates, or why something is or is not reachable.
---

# How URLs reach this VM

## The scheme

Everything for this project — the main name and the whole wildcard — arrives at
**Caddy inside this VM, on port 80**. Caddy then decides:

    <project>.appsmoothly.com             -> 127.0.0.1:8080   Campfire
    app.<project>.appsmoothly.com         -> 127.0.0.1:3000   your app
    <anything>.<project>.appsmoothly.com  -> your route files, else Campfire

The consequence worth internalising: **you can create new hostnames yourself.**
The wildcard already resolves and is already covered by the certificate, so a
route file in `/etc/caddy/routes/` is all it takes. See `deploy-previews`.

## The path a request takes

**Public projects:**

    browser -> VPS :443            TCP forwarded by SNI. No TLS termination,
                                   no HTTP parsing. It cannot read the traffic.
            -> tunnel              to the desktop
            -> Caddy               terminates TLS, checks login, proxies
            -> this VM :80 / :3000

**Tailnet-only projects** skip the VPS: the browser reaches the desktop directly
over the private network. The URL is the same either way.

## What this means for you

* **You never handle TLS.** Certificates are obtained and renewed outside this
  VM by DNS-01. There is nothing to install in here, and you should not run
  certbot or ask Caddy for automatic HTTPS.
* **You only ever see plain HTTP** arriving on `80` and `3000`.
* **The client IP you see is the proxy**, not the visitor. Use
  `X-Forwarded-For` if you need the real one.
* **Subdomains of this project are yours.** `*.<project>.appsmoothly.com`
  already points here and is already covered by the certificate — add a Caddy
  route file and it works.
* **A hostname outside that pattern** (a different apex, or a different
  project's name) needs DNS and proxy changes outside this VM. Ask the human.

## Exposure modes

| | tailnet-only | public |
|---|---|---|
| Who can reach it | the owner's own devices | anyone |
| Login | none — the tunnel is the auth | tinyauth (username + password) |
| URL | `https://<project>.appsmoothly.com` | `https://<project>.appsmoothly.com` |

Which mode this VM is in was decided when it was created and cannot be changed
from inside. If you are unsure, ask — it matters a great deal before you put
anything sensitive on a page.

## Checking

    # through the router, as the outside world arrives
    curl -sS -o /dev/null -H 'Host: x.appsmoothly.com' \
         -w '%{http_code}\n' http://127.0.0.1:80/          # -> Campfire, expect 302
    curl -sS -o /dev/null -H 'Host: app.x.appsmoothly.com' \
         -w '%{http_code}\n' http://127.0.0.1:80/          # -> your app

    # the backends directly
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/   # campfire
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/   # your app

If those work but the public URL does not, the problem is outside this VM and
you should say so rather than changing things in here.
