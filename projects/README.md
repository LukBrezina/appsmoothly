# projects/

Per-VM working directory. **Contents are gitignored** — nothing in here is
pushed to this repo.

    projects/once-campfire/    the chat app itself, if you want to modify it
    projects/<app>/            this project's application source

They are separate git repositories with their own remotes. Keeping them out of
this repo means a VM never receives another project's code, and this public
repo never carries application source.

## Give a project its own instructions

A project directory can carry its own `CLAUDE.md` and `.claude/skills/`, and
they are picked up **without starting a session there** — verified, both in the
main session and inside subagents:

    projects/myapp/
      CLAUDE.md                  conventions: package manager, ports, gotchas
      .claude/skills/deploy/SKILL.md   how to ship it

Ask "how do I deploy myapp?" from anywhere in the workspace and the project's
own skill is what answers. Platform skills (`running-a-service`,
`deploy-previews`) stay available alongside them, so the two levels compose.

This is the right home for anything project-specific. Do not put it in the
workspace `CLAUDE.md` — that file is shared by every project on every VM.
