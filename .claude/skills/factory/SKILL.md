---
name: factory
description: Give a piece of work its own disposable container — a run — copied from a template that always tracks the repo's main branch, with the app runnable inside and its own preview URL. Use when starting a feature or bugfix that should be isolated from the VM, when asked for a run, a fresh sandbox, or "test this on its own copy of the app", and when managing the template.
---

# The factory: a template, and runs copied from it

This VM can act as a **cell**: it holds one **template** container — the
project repo at **latest main**, toolchain and dependencies installed — and any
number of **runs**, disposable copies of that template. One run = one piece of
work: its own branch, its own copy of the app, and (usually) its own room whose
Claude session lives *inside* the container.

The template is the only deterministic part. A timer polls the repo every ten
minutes and refreshes it to main (`git pull`, `mise install`, `bin/setup`).
Everything app-specific beyond that — seeding, prod-data copies, schedules —
is your judgment, not configuration.

## The normal flow

    run new invoices                     # container run-invoices, branch "invoices"
    room new "Invoice export" --run invoices --brief "Build CSV export of invoices …"

That is the whole setup. The room's session now executes inside
`run-invoices`: every shell command, test run and file edit happens in the
container, working in `/home/dev/app` on branch `invoices`. The VM around it
is untouched.

Inside a run you are user `dev` with passwordless sudo. Install what the task
needs; the container is disposable. Start the app on **127.0.0.1:3000** inside
the run and it is already reachable at `https://invoices.<project>...` — the
preview route was wired by `run new`.

## Sleep is free, delete is forever

    run sleep invoices     # stopped: 0 RAM, all state kept
    run wake invoices      # back in seconds

A message in the run's room **wakes it automatically** — sleep aggressively.
When the PR is merged or the work abandoned:

    room archive "Invoice export" --purge    # removes the run + route too
    run rm invoices                          # or directly, if no room owns it

`rm` destroys the container. The branch and PR live on in git; anything not
pushed is gone. Push before you delete.

## Runs with prod-like data

A fresh run has whatever `bin/setup` built (usually seeds). For "how does this
behave on real data", load a dump *inside the run* with the app's own tools
(`pg_restore`, a sqlite copy, `bin/rails db:...`). Ask for a dump with
`ask-secret` or have the human place one — do not reach for production from
in here; this VM cannot and should not.

## Preconfigured runs: secret files the app needs

Some files must exist in the checkout but never enter git — Rails
`config/master.key` is the classic. Put them under `~/.secrets/app-files/`
mirroring their repo path:

    ask-secret RAILS_MASTER_KEY "to boot the app in runs"
    install -d -m 700 ~/.secrets/app-files/config
    secret RAILS_MASTER_KEY | tr -d '\n' > ~/.secrets/app-files/config/master.key

`template-build` injects everything under `app-files/` into the template on
every build and refresh (and reruns `bin/setup` when a file changed), so every
run is born with them — nothing is pasted per run, and the files live only in
this cell. Works for any path: `.env`, `config/credentials/*.key`, a service
account JSON.

## Managing the template

    sudo template-build https://github.com/OWNER/REPO.git   # once, when the cell is born
    sudo template-build                                     # refresh now (the timer does this too)

A private repo needs `ask-secret GITHUB_TOKEN "to clone <repo> into the
factory"` first — template-build picks the token up from `~/.secrets` and
copies it into the template so fetches keep working.

If a refresh fails (a broken `bin/setup` on main, usually), the template stays
on its last good state, new runs start from there, and the failure is posted
to chat for you to look at. Fix main, or fix the template by hand:
`incus exec template -- ...`.

## One-time cell setup

    sudo cell-init                          # incus + btrfs pool + fixed bridge
    sudo systemctl restart claude-bot       # so the bridge picks up incus rights
    ask-secret GITHUB_TOKEN "..."           # if the repo is private
    sudo template-build <git-url>

`cell-init` is idempotent and safe to re-run. Everything lives inside this VM;
nothing about the factory is visible outside it.

## Limits and honesty

- Runs are containers **inside** this VM: strong enough walls between pieces
  of work, but the VM is still the real security boundary.
- The preview route assumes the app listens on `127.0.0.1:3000` *inside the
  run*. A different port needs its own route file (see deploy-previews).
- `run list` is the inventory. If a run shows MISSING, its container was
  deleted outside `run rm` — clean the record with `run rm <name>`.
