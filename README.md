# appsmoothly

The workspace that lives **inside** a project VM: Claude skills, the Campfire
chat instance, and the Claude bot that connects them.

Each project gets its own disposable VM. Inside it you get a Campfire instance
on the project's main URL, with a Claude bot already in it — so you can talk to
Claude about the project from a phone, and it can edit code, run commands and
deploy from within that VM.

This repo is cloned into every VM. It deliberately contains **no host or
infrastructure configuration** — a VM should not carry a map of the machine
hosting it.

    CLAUDE.md              orientation for Claude running inside a VM
    .claude/skills/        how to do specific things in here
    campfire/              Campfire + Claude bot runtime (systemd units, bridge)
    projects/              per-VM project sources (gitignored)

See `CLAUDE.md` for how the pieces fit together.
