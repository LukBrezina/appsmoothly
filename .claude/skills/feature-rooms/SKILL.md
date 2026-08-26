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

## Open one

    room new "Search rewrite" --cwd /home/appsmoothly/projects/myapp-search

Prints the room's URL. It is an **open room** — everyone in the project can read
it, which is the point — and Claude answers every message in it without being
tagged.

The typical shape, for a project with worktrees:

    cd /home/appsmoothly/projects/myapp
    git worktree add ../myapp-search -b search-rewrite
    room new "Search rewrite" --cwd /home/appsmoothly/projects/myapp-search

Check the project's own `CLAUDE.md` first — how a project wants worktrees,
branches and ports set up is project-specific and lives there, not here.

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
