---
name: deploy-previews
description: Put a branch, PR or experiment on its own hostname inside this VM, using Caddy route files — creating, listing and tearing down previews. Use when asked for a preview, a staging URL, "show me this branch", or a second copy of the app on its own address.
---

# Preview deploys

The whole `*.<project>.appsmoothly.com` wildcard already points at this VM, and
Caddy in here decides where each hostname goes. So a preview is just **a route
file plus a process** — nothing outside the VM has to change, and no DNS record
or certificate is needed.

## Make one

Pick a port nobody is using and a hostname prefix:

    PREVIEW=pr-142
    PORT=4142

Start the thing on loopback (see `running-a-service` for a systemd unit — do
that if it should survive a reboot):

    cd ~/work/appsmoothly/projects/myapp
    git worktree add ../myapp-$PREVIEW origin/some-branch
    cd ../myapp-$PREVIEW
    bin/rails s -b 127.0.0.1 -p $PORT

Route to it:

    sudo tee /etc/caddy/routes/$PREVIEW.caddy >/dev/null <<CADDY
    @$PREVIEW header_regexp Host ^$PREVIEW\.
    handle @$PREVIEW {
        reverse_proxy 127.0.0.1:$PORT
    }
    CADDY
    sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy

It is now live at `https://pr-142.<project>.appsmoothly.com` — with a valid
certificate, because the wildcard covers it.

**Always `caddy validate` before reloading.** A broken route file takes down
Campfire too, since they share the same Caddy.

## Rules that matter

* **Route files are matcher + handle only.** No site address, no `:80` block —
  they are imported *inside* the existing one.
* **Matcher names must be unique** across all route files. Name them after the
  preview.
* **`app.` is taken** and matched before your routes. Do not shadow it.
* **The default is Campfire.** Any hostname you have not routed lands on chat,
  which is a reasonable fallback but means a typo looks like it "works".

## List and tear down

    ls /etc/caddy/routes/
    sudo rm /etc/caddy/routes/pr-142.caddy
    sudo systemctl reload caddy
    git worktree remove ../myapp-pr-142

Tear previews down when the branch merges. They cost a process and a port each,
and this VM is not large.

## Exposure

A preview inherits the project's exposure. On a **public** project it is
reachable by anyone who gets past the login; on a **tailnet-only** project it is
visible only on the owner's own devices. Check which you are in — see
`urls-and-routing` — before putting real data in a preview.
