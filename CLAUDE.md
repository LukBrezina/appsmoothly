# Where you are

You are running inside a **disposable per-project VM**. It is a real KVM virtual
machine (Incus), not a container, on a Windows desktop running WSL2. One VM per
project; they cannot reach each other.

This means you can be destructive here. The VM is snapshotted daily and can be
rolled back in about a second, and the whole thing is meant to be thrown away.
Do not be timid about installing packages, editing system files or restarting
services — that is what this box is for.

## What is already running

| | |
|---|---|
| **Campfire** | chat, Docker container, on port `80`. The project's main URL. |
| **Claude bot** | `claude-bot.service` — a bridge from Campfire to `claude -p` |
| **Docker** | installed and running |
| **Caddy** | installed but **not** enabled; use it if you need in-VM routing |
| Your user | `lukas`, passwordless sudo |

The human talks to you through Campfire, often from a phone. Messages you
receive there are chat messages; what you output is posted back to the room.
Keep chat replies short — summaries, not walls of text.

## URLs

    https://<project>.appsmoothly.com          -> Campfire (port 80)
    https://app.<project>.appsmoothly.com      -> your app (port 3000)
    https://<anything>.<project>.appsmoothly.com -> Campfire (wildcard)

TLS terminates outside this VM. You will only ever see plain HTTP arriving on
those ports, and there is no certificate to manage in here.

Two exposure modes, decided when the VM was created:

* **tailnet-only** — reachable only from the owner's own devices. URLs carry an
  explicit `:8443`. No login.
* **public** — reachable from anywhere, behind a login (tinyauth).

You cannot change which mode you are in from inside the VM. Ask the human.

## Ports

Only `80`, `3000` and `22` are reachable from outside the VM; a firewall rule
outside drops the rest. Bind services to `0.0.0.0`, not `127.0.0.1`, or the
proxy in front cannot reach them.

If you need more than one HTTP service exposed, run Caddy in here as a local
router in front of them rather than asking for more ports.

## Credentials

`/etc/claude/oauth-token` is root-owned `0600` and holds the subscription token
that authenticates you. Do not print it, copy it into a shell profile, commit
it, or pass it to anything.

**`ANTHROPIC_API_KEY` must stay unset.** If it is set it silently overrides the
subscription token and bills per request. `/etc/profile.d/00-anthropic-guard.sh`
strips it, and the `claude` wrapper unsets it again. Rails `.env` files are the
usual way it sneaks back in — check for it before sourcing anything.

## Things that are not here, on purpose

There is no infrastructure tooling in this VM: no host configuration, no VPS
details, no DNS credentials, nothing that describes the machine hosting you.
That is deliberate. If a task seems to need it, it belongs on the host and you
should ask the human rather than trying to reach out.

## Layout

    ~/work/appsmoothly/        this repo
      .claude/skills/          how to do specific things
      campfire/                Campfire + bot runtime
      projects/                project sources (gitignored, per-VM)
