# CLAUDE.md

Read the README first — its "Architecture" section is the handoff document:
big picture, the one session, the publish dir, and a Gotchas list of
non-obvious constraints (bundler-env stripping into tmux, Turbo Drive
deliberately off, claude's process title, xterm FitAddon padding,
tailwind-watcher TTY). Don't undo those without reading why.

## Commands

- `bin/rails test` — the suite (fast; includes a real shell test of the launch command)
- `bin/rails tailwindcss:build` — required after CSS/token changes if no watcher runs
- `APPSMOOTHLY_PROJECTS_DIR=<dir> bin/dev` — run locally (foreman needs a TTY; headless: `tailwindcss:build` + `bin/rails server`)

## Hard rules

- **The factory is a terminal and a first-run page. That's the product.** One
  tmux session named `claude`, always available, running in
  `<projects>/<APPSMOOTHLY_APP>`. Everything else — sessions, worktrees, dev
  servers, deploys, previews, email, rollbacks — is claude's job, done through
  the shell it already has. Don't add a button for something claude can do and
  explain.
- **No database.** `Agent.alive?` asks tmux; the filesystem holds the app. There
  are zero tables and no models with state. If you find yourself wanting a row,
  you're rebuilding what was deleted.
- **`config/claude-brief.md` is the product**, attached to every launch with
  `--append-system-prompt-file`. Non-technical voice, no diffs, proactive next
  steps, and the box's wiring (kamal settings, env vars, `$PORT`, the publish
  dir). New box capability → a paragraph there, not a controller.
- **The publish dir (`~/public` → `/ui`) is claude's UI surface.** It writes or
  symlinks HTML and hands the user a link. That is how an inbox, a version
  list, or a chart gets built now. Symlinks are followed on purpose.
- Claude defaults are injected per-launch (`--permission-mode auto --settings
  config/claude-settings.json --append-system-prompt-file config/claude-brief.md`)
  and the app dir is pre-trusted (`Factory.trust!`) — never edits the box's
  global claude config.
- Launch is `claude … --continue || claude … "<first prompt>"`: a reboot resumes
  the conversation, a fresh box gets its first task. `Agent#at_a_shell?` restarts
  claude if the user quit out of it. Both covered by `test/models/agent_test.rb`.
- Localhost-only: the factory binds loopback (`config/puma.rb`) and has no
  in-app auth gate — the network is the boundary (Caddy + Authelia in front on a
  provisioned box). Don't reintroduce an app-level password.
- Voice on a headless box: the browser streams mic audio (16 kHz mono PCM) over
  `MicChannel` into a PulseAudio pipe-source (`Mic`, the default input), so
  claude's own `/voice` records it and transcribes with Anthropic's model. The
  🎤 button opens the mic; hold SPACE to talk. **Provisioning
  (appsmoothly-infra) must install `pulseaudio pulseaudio-utils sox` and run a
  per-user pulse daemon (`--exit-idle-time=-1`)** — the factory only creates the
  virtual source. `bin/mic-proof` is the box-side sanity check.
- All UI copy targets someone who never coded: deploy→"go live", "try it",
  "pages". The brief holds claude to the same voice.
- Provisioning's only jobs now: install claude/tmux/kamal/pulse, set the
  `APPSMOOTHLY_*` env, create `<projects>/`, run the factory. It no longer
  creates or clones an app — the first-run page hands that to claude.
