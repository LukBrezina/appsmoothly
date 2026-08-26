---
name: feature-rooms
description: Give a piece of work its own chat room, its own Claude session and its own preview URL — creating, listing and closing them with the `room` command. Use when starting a feature, when a conversation should be split off, or when asked to "open a room for this" or close one that is finished.
---

# One room, one feature, one session

Every Campfire room is a **separate Claude session**. Different room, different
conversation, different context. A room can also run in its **own directory**,
so two features can work on the same repo without fighting over one checkout.

That makes a room the natural unit of work: open one when a feature starts,
close it when the feature ships.

## The thing to understand first

**You are one session, and it belongs to one room.** Everything you say goes to
*your* room. Creating another room does not move you into it, and you will not
see what is said there.

**A room with nothing in it has no session at all.** The session starts when
someone speaks. So `room new` on its own produces a room that sits empty and
looks broken — the work carries on in the room you were already in, which is
exactly what you did not want.

So when you open a feature room, **hand the work over in the same breath**:

    room new "Search rewrite" \
      --cwd /home/appsmoothly/projects/myapp-search \
      --brief "Rewrite search to use a GIN index. Start by reading db/schema.rb
               and app/models/concerns/searchable.rb, then propose an approach."

`--brief` posts that message into the new room and starts its session there, in
its own directory. Then say one line where you are — "→ opened #Search rewrite,
continuing there: <url>" — and **stop working on it here**. Two sessions doing
the same job is worse than one.

## Open one

    room new "Search rewrite" --cwd DIR --brief "what to do"

Prints the room's URL. It is an **open room** — everyone in the project can read
it, which is the point — and Claude answers every message in it without being
tagged.

The typical shape, for a project with worktrees:

    cd /home/appsmoothly/projects/myapp
    git worktree add ../myapp-search -b search-rewrite
    room new "Search rewrite" --cwd /home/appsmoothly/projects/myapp-search \
      --brief "..."

Check the project's own `CLAUDE.md` first — how a project wants worktrees,
branches and ports set up is project-specific and lives there, not here.

## Models

A feature room runs on **opus** by default; ordinary chat runs on **sonnet**.
That split is the point — a question should be cheap, and the phase where code
gets written should not be answered by the fast model.

    room new "Search rewrite" --cwd DIR --brief "..." --model fable
    room watch "Search: Full-text (GIN)" --model opus     # change an existing one

`room list` shows each room's model. Changing it ends that room's session so
the next message starts on the new one; the conversation is preserved.

If a *whole project* should chat on something stronger, that is
`CLAUDE_MODEL` in `~/.config/claude-bot/config.env` plus
`systemctl restart claude-bot` — but prefer per-room, so asking a question
stays cheap.

## Speaking into a room you are not in

    room say "All Talk" "Search rewrite is merged; closing that room."

Use it to report back when a feature is done, or to hand something over. It is
the only way to say anything outside your own room.

## Give it a URL

A feature room usually wants somewhere to click. Run the branch on its own port
and route a hostname to it — see the `deploy-previews` skill. Name the hostname
after the room:

    https://search-rewrite.<project>.appsmoothly.com

Post that link in the room once it is up.

## Close one

    room close "Search rewrite"

Deletes the room and ends its Claude session. **It does not clean up anything
else** — the worktree, the route file and the service are yours to remove:

    sudo rm /etc/caddy/routes/search-rewrite.caddy && sudo systemctl reload caddy
    git -C /home/appsmoothly/projects/myapp worktree remove ../myapp-search

Close a room when its work is merged. You may do this yourself when a feature is
genuinely finished; say so in the room first.

## The rest of the commands

    room list                    every room: watched or tag-only, and its directory
    room say <room> "text"       post into a room you are not in
    room watch "All Talk"        answer everything here, no tagging
    room unwatch "All Talk"      back to tag-only

`room close` refuses to touch **AppSmoothly**, **All Talk**, **System** and any
direct room. Those are standing rooms, not feature rooms.

## How it works, briefly

Campfire only delivers a message to a bot in a direct room, or when the bot is
mentioned. A one-line addition in
`campfire/initializers/appsmoothly_agent_rooms.rb` widens that to honour the
membership's `involvement`, so an open room whose bot membership is
`everything` behaves like a DM — public to the team, live for Claude. `room`
is what sets that, plus the room-to-directory mapping the bridge reads.
