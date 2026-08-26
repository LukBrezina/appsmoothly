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
| **Campfire** | chat, Docker container, internal on `127.0.0.1:8080`. Unconfigured until a human completes `/first_run` |
| **Claude bot** | `claude-bot.service` — a bridge from Campfire to `claude -p` |
| **Docker** | installed and running |
| **Caddy** | **the router**. Owns `:80`; everything from outside arrives here |
| Your user | `lukas`, passwordless sudo |

The human talks to you through Campfire, often from a phone. Messages you
receive there are chat messages; what you output is posted back to the room.
Keep chat replies short — summaries, not walls of text.

**Anything with structure goes on a page, not into chat.** A table, a
comparison, a plan, a long code block: write it to `/srv/notes/<name>.html` and
reply with the link. See the `publishing-notes` skill. Chat carries the verdict;
the page carries the detail.

Rooms are the unit of work. **Every room is a separate Claude session**, and a
room can run in its own directory — so a feature gets its own room, its own
conversation and its own worktree. Open one with `room new`, close it when the
work ships. See the `feature-rooms` skill.

Two consequences that are easy to get wrong: **everything you say goes to your
own room** — creating another room does not move you into it — and **a room
nobody has spoken in has no session**. So open a feature room *with its work*,
`room new ... --brief "..."`, which starts the session there; then say where you
went and stop working on it here. `room say <room> "..."` is how you speak into
a room you are not in.

A room is either **watched** — you answer every message in it, no tagging — or
**tag-only**. `room list` says which. All of them are ordinary open rooms that
everyone in the project can read; none of this depends on a private DM, so a
colleague can follow any of it.

* **#All Talk** — watched. The main conversation, and where you land.
* **feature rooms** — watched, one per piece of work, created by `room new`.
* **#System** — tag-only. Automated notices: update results, failures, anything
  the platform reports. Post here with `notify "..."`, or `notify --ask "..."`
  for a message that also asks you to act.
* **#All Talk** and any other open room — tag-only. You only see a message there
  if someone mentions you.

A direct message to the bot also reaches you, always — Campfire delivers every
message in a direct room. Use it the same way; it is just not public.

## URLs

    https://<project>.appsmoothly.com          -> Campfire (port 80)
    https://app.<project>.appsmoothly.com      -> your app (port 3000)
    https://notes.<project>.appsmoothly.com    -> /srv/notes — pages you publish
    https://<anything>.<project>.appsmoothly.com -> Campfire (wildcard)

TLS terminates outside this VM. You will only ever see plain HTTP arriving on
those ports, and there is no certificate to manage in here.

Two exposure modes, decided when the VM was created:

* **tailnet-only** — reachable only from the owner's own devices. No login.
* **public** — reachable from anywhere, behind a login (tinyauth).

You cannot change which mode you are in from inside the VM. Ask the human.

## Ports

Only **`80` and `22`** cross the VM boundary. Port `80` is Caddy, which routes
by hostname to whatever is inside:

    :80  Caddy  ->  app.*      -> 127.0.0.1:3000   your app
                ->  /etc/caddy/routes/*.caddy      your own routes
                ->  everything else -> 127.0.0.1:8080   Campfire

So your services bind **`127.0.0.1`**, not `0.0.0.0` — only Caddy needs to be
externally reachable, and keeping backends on loopback means nothing is exposed
by accident.

Adding a hostname no longer needs anything outside the VM: the whole
`*.<project>` wildcard already points here, so a new route file is enough. See
the `deploy-previews` skill.

## Credentials

Need a token you do not have? **Do not ask for it in chat.** Run
`ask-secret NAME "why"` and the human gets a one-time paste form; see the
`secrets` skill.

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

## Getting a shell here

`ssh <project>.vm`, from a device on the owner's tailnet. The project's **web**
hostname (`<project>.appsmoothly.com`) is not this machine — it points at the
proxy in front of you.

## What this VM can and cannot reach

Assume this box is treated as untrusted, because it is: it runs agents with
permissions off, and its packages may be old.

**Outbound, you can reach the public internet and your own bridge gateway (for
DNS). Nothing else.** Explicitly blocked at the hypervisor:

    100.64.0.0/10    the owner's tailnet, including their production machines
    10.0.0.0/8       other projects' VMs
    172.16.0.0/12    the WSL host and the owner's daily-driver machine
    192.168.0.0/16   the home LAN
    169.254.0.0/16   link-local and cloud metadata endpoints

**Inbound, only the bridge gateway reaches you**, on `:80` and `:22`. Nothing
on the internet can open a connection to this VM directly.

If something you are asked to do needs to reach one of those blocked ranges,
it does not belong in here. Say so rather than trying to tunnel around it.

## Models

Chat runs on **Sonnet** — fast, and most messages are questions. Heavier work is
delegated to a subagent with a stronger model rather than upgrading the whole
conversation:

    .claude/agents/implementer.md   opus    writes and changes code
    .claude/agents/researcher.md    sonnet  reads across files to answer

Use them. A refactor or a bug fix should go to `implementer`, not be typed out
in the chat session. Their output is forwarded into the room as it happens, so
delegating does not hide progress.

## Layout

`/home/appsmoothly` **is** this repo, and it is your working directory.

    /home/appsmoothly/
      CLAUDE.md            this file
      .claude/skills/      how to do specific things
      .claude/agents/      subagents, each pinned to a model
      campfire/            Campfire + bot runtime — this is the live runtime,
                           not a copy of it (see below)
        initializers/      additive patches to Campfire, applied at image build
        routes/            Caddy route files shipped to every VM
      projects/            project sources (gitignored, per-VM)
        once-campfire/     Campfire's own source, tracking upstream

### Per-project instructions

A project can carry its own `CLAUDE.md` and `.claude/skills/`, and they are
picked up without starting a session there — in subagents too:

    projects/myapp/
      CLAUDE.md                        conventions: package manager, ports
      .claude/skills/deploy/SKILL.md   how to ship it

Project-specific knowledge belongs there, not in this file. This one is shared
by every project on every VM.

## This repo updates itself

`appsmoothly-update.timer` fast-forwards `/home/appsmoothly` from `origin/main`
**hourly**, so skills and instructions stay current without redeploying a VM.

If it *cannot* fast-forward — local edits, local commits, a genuine conflict —
it does not stop silently. It **posts into Campfire and asks you (the bot) to
resolve it**, rate-limited to once every 6 hours. So if you find a message in
chat about the workspace repo failing to update, that is this: read the status
it included, get the tree clean and HEAD matching `origin/main`, keep anything
deliberate, discard obvious scratch, and never touch `projects/`.

    sudo /usr/local/sbin/appsmoothly-update      # run it now and see
    git -C /home/appsmoothly status --short

`campfire/` in this repo is not documentation of the runtime, it **is** the
runtime. When the update pulls a change there, `appsmoothly-install` puts it
into service — the bridge into `/opt/claude-bot`, the commands into
`/usr/local/bin`, the units into systemd, the route files into Caddy, the
initializers into the Campfire image — and restarts only what changed. So a
change pushed to this repo reaches VMs that already exist, not just the next one
built. Run it by hand after editing anything in there:

    sudo /usr/local/sbin/appsmoothly-install

`projects/` is gitignored, so working in there never blocks updates.

Campfire's own source updates the same way on a daily timer
(`campfire-update.timer`): fetch, fast-forward, rebuild the image, restart. The
Docker volume holds the database, so messages survive a rebuild.
