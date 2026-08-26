---
name: running-a-service
description: Run an app or service inside a project VM so it is reachable from outside — choosing a port, binding correctly, and keeping it alive across reboots with systemd. Use when asked to start, expose, deploy or daemonise anything in the VM.
---

# Running a service in the VM

## Which port

| Port | Who | Notes |
|---|---|---|
| `80` | **Caddy** | the only HTTP port that crosses the VM boundary |
| `8080` | Campfire | loopback only |
| `3000` | **your app** | loopback only; Caddy sends `app.*` here |
| `22` | ssh | |
| anything else | free | reachable through Caddy, not directly |

Caddy owns `:80` and routes by hostname. Everything behind it stays on
loopback, so you cannot accidentally expose a service by binding it.


## Rails in development: the Host header will 403 you

A Rails app in `development` blocks unknown `Host` headers, and every request
reaches you as `app.<project>.appsmoothly.com` from the router. So the app works
on `127.0.0.1:3000` and returns **403 Blocked hosts** through Caddy — which
looks like a routing bug and is not one.

Allow the project's own domain in the unit:

    Environment=RAILS_DEVELOPMENT_HOSTS=.<project>.appsmoothly.com

**The leading dot allows exactly one extra label.** `.appsmoothly.com` compiles
to `/\A([a-z0-9-]+\.)?appsmoothly\.com\z/`, which matches
`<project>.appsmoothly.com` but *not* `app.<project>.appsmoothly.com` — so the
obvious-looking value silently 403s every app request. Use the **project**
domain and both `app.` and every preview hostname work.

Check the allowlist rather than guessing at it:

    RAILS_ENV=development RAILS_DEVELOPMENT_HOSTS=.<project>.appsmoothly.com \
      bin/rails runner 'p ActionDispatch::HostAuthorization::Permissions
        .new(Rails.application.config.hosts)
        .allows?("app.<project>.appsmoothly.com")'

Running in `production` instead avoids this entirely, but needs
`config/master.key` — which is gitignored, so it is not in a fresh checkout.
Ask for it with `ask-secret RAILS_MASTER_KEY` rather than through chat.

## Bind to 127.0.0.1

    rails s -b 127.0.0.1 -p 3000
    node server.js --host 127.0.0.1 --port 3000
    python -m http.server 3000 --bind 127.0.0.1

Check:

    ss -tlnp | grep 3000        # 127.0.0.1:3000 is correct here

## Make it survive a reboot

Do not leave things running under `nohup`. The VM restarts — after a host
reboot, after a snapshot rollback — and anything not managed by systemd is gone.

    sudo tee /etc/systemd/system/myapp.service >/dev/null <<'UNIT'
    [Unit]
    Description=My app
    After=network-online.target
    Wants=network-online.target

    [Service]
    User=lukas
    WorkingDirectory=/home/appsmoothly/projects/myapp
    ExecStart=/usr/bin/env bash -lc 'bin/rails s -b 0.0.0.0 -p 3000'
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target
    UNIT
    sudo systemctl daemon-reload && sudo systemctl enable --now myapp
    systemctl status myapp --no-pager

Use `EnvironmentFile=` for configuration. Never put secrets in `ExecStart` —
it is visible in `ps` and `systemctl show` to every user on the box.

## More than one HTTP service

Only one thing can own `:3000`. If you need several, enable Caddy as a local
router and point everything at it:

    sudo tee /etc/caddy/Caddyfile >/dev/null <<'CADDY'
    :3000 {
        @admin host admin.myproject.appsmoothly.com
        handle @admin { reverse_proxy 127.0.0.1:4001 }
        handle { reverse_proxy 127.0.0.1:4000 }
    }
    CADDY
    sudo systemctl enable --now caddy

Now the backends can bind `127.0.0.1` — only Caddy needs `0.0.0.0`. Note this
only distinguishes hostnames that already route here; see the
`urls-and-routing` skill for which ones do.

## Debugging a 502

A 502 in the browser means the proxy reached this VM but nothing answered.

    systemctl status myapp --no-pager     # is it running?
    ss -tlnp | grep 3000                  # is it bound at all?
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/     # direct
    curl -sS -o /dev/null -H 'Host: app.x.appsmoothly.com' \
         -w '%{http_code}\n' http://127.0.0.1:80/                        # via Caddy
    journalctl -u myapp -n 50 --no-pager
    journalctl -u caddy -n 30 --no-pager

If direct works but via-Caddy 502s, the route is wrong. If both 502, the app is
not up.
