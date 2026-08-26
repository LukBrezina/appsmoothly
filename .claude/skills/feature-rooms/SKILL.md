---
name: feature-rooms
description: Give a piece of work its own chat room, its own Claude session, its own model and its own preview URL — opening one, handing the work over, and archiving it when the feature ships. Use when starting a feature, when a conversation should be split off, or when work in a room is finished.
---

# One room, one feature, one session

Every Campfire room is a **separate Claude session**. Different room, different
conversation, different context, and its **own working directory and model**.

That makes a room the natural unit of work: open one when a feature starts,
archive it when the feature ships.

## The thing to understand first

**You are one session, and it belongs to one room.** Everything you say goes to
*your* room. Creating another room does not move you into it, and you will not
see what is said there.

**A room with nothing in it has no session at all.** The session starts when
someone speaks.

So open a feature room **with its work in the same breath**:

    room new "Search rewrite" \
      --cwd /home/appsmoothly/projects/myapp-search \
      --brief "Rewrite search onto a GIN index. Read db/schema.rb and
               app/models/concerns/searchable.rb first, then propose an approach."

That creates the room, posts the brief, and starts the session there. It also
**announces the handover in the room you were in**, with a link — so the
conversation that asked for this does not just go quiet. You do not need to
repeat that announcement; say at most one line of your own and then **stop
working on it here**. Two sessions doing the same job is worse than one.

## Models

A feature room runs on **opus** by default; ordinary chat runs on **sonnet**. A
question should be cheap; the phase where code gets written should not be
answered by the fast model.

    room new "..." --model fable          # at creation
    room set "Search rewrite" --model opus   # afterwards

`room list` shows each room's model. Changing it ends that room's session so the
next message starts on the new model; the conversation is kept.

## Give it a URL

A feature room usually wants somewhere to click. Run the branch on its own port
and route a hostname to it — see `deploy-previews`. Then **record it**, so the
room can clean up after itself later:

    room set "Search rewrite" --route search-rewrite --service myapp-search

Post the link in the room once it is up.

## Finishing: offer to archive

When the work is merged, or you believe it is done, **do not archive it
yourself.** Say so and ask:

> Search rewrite is merged and the preview matches what we agreed. Happy for me
> to archive this room and tear down the worktree and preview?

Only once they say yes:

    room archive "Search rewrite" --purge

**Archive keeps the conversation.** The room drops out of the sidebar, its
session ends, and every message stays — `room watch "Search rewrite"` brings it
back. `room close` is the destructive one: it deletes the room and its history,
so use it for a room opened by mistake, not for finished work.

`--purge` tears down **only what was recorded** with `room set` — the route
file, the systemd unit — plus the working directory *if it is a linked git
worktree and clean*. It refuses to touch a real clone, and refuses to discard
uncommitted changes. Anything it declined to remove, it says so.

Before archiving, put the outcome somewhere that outlives the room:

    room say "All Talk" "Search rewrite shipped: GIN index, ~40x on the common
                         query. Details: https://notes.<project>.appsmoothly.com/search-rewrite.html"

## What belongs here, and what belongs to the project

This skill is the **platform**: rooms, sessions, models, and tearing down what a
room was told it owns. It is the same on every project.

The **project** owns what a feature actually is:

* how worktrees and branches are named
* which port a preview runs on, and how to start and stop it
* what "done" means — tests, review, a migration having run
* whether anything must be merged or deployed before a room is archived

That lives in `projects/<name>/CLAUDE.md` and `projects/<name>/.claude/skills/`,
and you should read it **before** opening a room for that project. If a project
has no such instructions and the answer matters, ask rather than invent one.

The seam between them is `room set`: the project decides what it built, and
records it, so the platform can take it down without guessing. That is
deliberate — guessing what a project built is how you delete someone's work.

## The rest of the commands

    room list                    every room: watched/archived, model, directory
    room say <room> "text"       post into a room you are not in
    room watch <room>            answer everything here, no tagging
    room unwatch <room>          back to tag-only

`archive` and `close` both refuse **All Talk**, **System**, **AppSmoothly** and
any direct room. Those are standing rooms, not feature rooms.

## How it works, briefly

Campfire only delivers a message to a bot in a direct room, or when the bot is
mentioned. `campfire/initializers/appsmoothly_agent_rooms.rb` widens that to
honour the membership's `involvement`, so an open room whose bot membership is
`everything` behaves like a DM — public to the team, live for Claude. `room` is
what sets that, plus the per-room directory, model and teardown facts the bridge
and `--purge` read.
