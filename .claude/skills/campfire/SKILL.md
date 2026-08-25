---
name: campfire
description: Work with this VM's Campfire chat instance and the Claude bot in it — how the bridge works, restarting it, reading room history, admin access, and modifying Campfire itself. Use when asked about chat, the bot, Campfire, rooms, or when replies stop arriving.
---

# Campfire and the Claude bot

Campfire is this project's chat, on the main URL. A bot user called **Claude**
is in it, wired to a local bridge. When the bot is mentioned in a room (or
receives any message in a direct room), the bridge runs `claude -p` here and
posts the reply back.

**You are usually that bot.** Chat messages are what you receive; your output is
posted into the room.

## A fresh VM starts unconfigured

Nothing pre-creates an account. On first boot Campfire is running but empty, and
the main URL lands on **`/first_run`** ("Set up Campfire") where the human
chooses their own name, email and password.

The bot cannot exist before an account does, so it is created *afterwards*:
`campfire-bot-init.timer` checks every 30s, and once a human has completed
first-run it creates the Claude bot, writes the bridge config and starts
`claude-bot`, then disables itself. Expect the bot to appear within a minute of
setup.

If the bot never shows up:

    systemctl status campfire-bot-init.timer --no-pager
    sudo /usr/local/sbin/campfire-bot-init      # run it now and see why

## The pieces

| | |
|---|---|
| `campfire.service` | Docker container, port `80`, data in volume `campfire` |
| `claude-bot.service` | `/opt/claude-bot/bridge.py`, listens on the Docker gateway `:4488` |
| `~/.config/claude-bot/config.env` | bridge config, `0600` — bot key and webhook secret |
| `/etc/campfire/env` | `SECRET_KEY_BASE`, VAPID keys, `0600` |
| `campfire-bot-init.timer` | waits for first-run, then creates the bot |

Every VM generates its **own** `SECRET_KEY_BASE`, VAPID keypair and bridge
secret on first boot. Nothing is shared between projects, and no credentials are
invented for you — the admin login is whatever you set at first-run.

## When replies stop arriving

    systemctl status claude-bot campfire --no-pager
    journalctl -u claude-bot -n 50 --no-pager
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:80/up   # want 200

The bridge listens on the **Docker bridge gateway**, not localhost, because the
Campfire container has to reach it. Confirm the webhook still points at the
address the bridge is actually bound to:

    ss -tlnp | grep 4488
    sudo docker exec campfire bin/rails runner \
      'puts User.active_bots.first.webhook&.url'

Those two must agree. They can drift if the Docker bridge subnet changes.

    sudo systemctl restart claude-bot

## Reading room history

The bridge only passes you recent messages. For more:

    /opt/claude-bot/history <room-id> [count]     # default 50

The room id is in the header of each message you receive.

## Admin access

Whatever you chose at first-run. If you have lost it, reset the password from
the Rails console rather than rebuilding:

    sudo docker exec -it campfire bin/rails console
    > User.find_by(email_address: 'you@example.com').update!(password: 'new-password')

The bot only sees rooms it is a member of, so invite it to any room you want it
in.

## Rails console

Campfire is a Rails app in a container:

    sudo docker exec -it campfire bin/rails console
    sudo docker exec campfire bin/rails runner 'puts User.count'

Useful models: `User` (`role: :bot` for bots, `bot_key` for the API key),
`Room`, `Message`, `Webhook`, `Account`.

## Changing Campfire itself

The source is checked out at `projects/once-campfire`, tracking
`basecamp/once-campfire` with no local patches. **The running container is built
from exactly this checkout**, so what you read there is what is running.

Edit, rebuild, restart:

    cd /home/appsmoothly/projects/once-campfire
    # ... make your changes ...
    sudo DOCKER_BUILDKIT=1 docker build -t campfire:local .
    sudo systemctl restart campfire

`DOCKER_BUILDKIT=1` is **required** — the Dockerfile uses `COPY --chmod`, which
the legacy builder rejects outright. Without it the build dies around step 25.

The container keeps its data in the `campfire` Docker volume, so rebuilding does
not lose messages. **Do not delete that volume** — it holds the database and
every uploaded file.

### Staying current with upstream

    sudo /usr/local/sbin/campfire-update            # fetch, rebuild, restart
    sudo /usr/local/sbin/campfire-update --force    # rebuild even if unchanged

This runs on a daily timer. It is fast-forward only, so **local commits in that
checkout will block it** — the same tradeoff as the workspace repo. If you have
changes worth keeping, push them to your own fork and repoint `origin`.

### Where to put a change

Nothing is applied on top of upstream, so a local edit here diverges silently.
Prefer changing Campfire through its own configuration or a Rails initializer
where possible; reserve source edits for things that genuinely cannot be done
otherwise, and expect to maintain them.
