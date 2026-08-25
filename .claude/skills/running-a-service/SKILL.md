---
name: running-a-service
description: Run an app or service inside a project VM so it is reachable from outside — choosing a port, binding correctly, and keeping it alive across reboots with systemd. Use when asked to start, expose, deploy or daemonise anything in the VM.
---

# Running a service in the VM

## Which port

| Port | Reachable from outside | Use |
|---|---|---|
| `80` | yes | taken by Campfire — leave it alone |
| `3000` | yes | **your app** (`app.<project>.appsmoothly.com`) |
| `22` | yes | ssh |
| anything else | **no** | internal only |

A firewall outside this VM drops everything else, so a service on `:4000` is
invisible no matter how correctly it runs. Either use `3000`, or put Caddy in
front (below).

## Bind to 0.0.0.0

The proxy that serves your app is **outside** this VM. A service bound to
`127.0.0.1` is unreachable, and this is the single most common reason a service
"works" locally and 502s from the browser.

    rails s -b 0.0.0.0 -p 3000
    node server.js --host 0.0.0.0 --port 3000
    python -m http.server 3000 --bind 0.0.0.0

Check what you actually bound:

    ss -tlnp | grep 3000        # want 0.0.0.0:3000, not 127.0.0.1:3000

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
    WorkingDirectory=/home/lukas/work/appsmoothly/projects/myapp
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
    ss -tlnp | grep -E ':(80|3000) '      # is it bound to 0.0.0.0?
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
    journalctl -u myapp -n 50 --no-pager
