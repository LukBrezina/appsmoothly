# Appsmoothly

A browser terminal with Claude in it, on a box that can put your app on the
internet. You talk (or type) to Claude in plain language; it builds the app,
runs it, shows it to you, and deploys it. There is no dashboard to learn —
if Claude needs to show you something, it builds the page and sends you the
link.

Status: the factory itself is verified end-to-end locally. The provisioned
box (Caddy + Authelia + backups) is implemented in
[appsmoothly-infra](https://github.com/LukBrezina/appsmoothly-infra) and has
not yet run against a real VPS.

---

## User guide

### Get started

Boxes are provisioned with OpenTofu (private repo `appsmoothly-infra`): one
VPS per customer, running Caddy + Authelia in front of this factory, a backup
bucket that refuses deletions, and a mail relay. Once the DNS records exist,
open `https://terminal.<customer>.appsmoothly.com` and sign in.

The first screen asks for two things:

1. **Allow** notifications, clipboard and microphone (one tap — voice and
   copy-from-terminal need it).
2. **Sign Claude in.** A terminal opens, a sign-in link appears as a button.
   That's the only credential the factory ever waits for; Claude signs you into
   GitHub itself, later, when your code first needs saving online.

Then pick what to start from — the Appsmoothly starter app, or a repo you
already have — and Claude takes it from there.

**Updating the factory**: `cd ~/appsmoothly && bin/update` (pull, migrate,
restart).

**Local development of the factory itself**:
`bin/setup && APPSMOOTHLY_PROJECTS_DIR=~/somewhere bin/dev` (or
`bin/rails tailwindcss:build && bin/rails server` — see the tailwind gotcha).

### The one screen

A terminal, and three buttons above it:

- **🎤** — talk instead of typing. Click it, then hold SPACE while you speak.
- **TRY IT** — your app, running, as you're building it.
- **PAGES** — anything Claude has published for you: a preview of an email your
  app sent, a list of versions you can rewind to, a chart, whatever it decided
  you needed to see.

Everything else happens in the conversation. Ask for a feature, ask to go live,
ask to undo yesterday — Claude does it and tells you what happened in plain
language.

### Bring your own app

Any app works. The one thing that has to be right is its `config/deploy.yml`
(Kamal) — and Claude writes that itself the first time you go live, using the
box's settings (see `config/claude-brief.md`). Nothing else is injected into
your repo: no hook files, no factory-specific plumbing.

### Going live, and rewinding

Ask. Claude commits your work, writes/updates `config/deploy.yml`, runs
`kamal setup` (first time) or `kamal deploy`, and reports progress in plain
language. If the box has a backup bucket (`APPSMOOTHLY_S3_*`), Claude wires up
Active Storage and a litestream accessory on that first deploy, so the live
database streams to a bucket that refuses deletions — that's what "rewind to
Tuesday" runs on.

---

## Architecture (for whoever hacks on this next)

### Big picture

- Vanilla Rails 8.1 (Tailwind v4, importmap). **No database** — zero tables.
- **One tmux session, named `claude`**, running in `<projects>/<APPSMOOTHLY_APP>`
  with `PORT=3100`. tmux is the only state there is: `has-session` answers
  "is it alive", and if it isn't, the next page load starts it.
- The factory owns exactly three things: the browser terminal, the first-run
  page, and a static file mount. Claude owns everything else and has a real
  shell to do it with.
- **`config/claude-brief.md` is where the product lives.** It's attached to
  every launch with `--append-system-prompt-file`, and it holds the voice rules
  (plain language, no diffs, always offer next steps) plus the box's wiring:
  the exact kamal settings this machine needs, the env vars available, `$PORT`,
  and the publish dir. Features are paragraphs there, not controllers.

### Key files

| file | role |
|---|---|
| `lib/factory.rb` | box facts: app dir, publish dir, domain, preview URL, `clean_tmux!`, `trust!` |
| `app/models/agent.rb` | the one claude session: `alive?`, `ensure!`, the launch command, tmux styling |
| `app/models/onboarding.rb` | first run: is claude signed in, the sign-in terminal, the sign-in URL scraper, the starter → first prompt |
| `app/models/mic.rb` | the box's virtual microphone (PulseAudio pipe-source) |
| `app/models/ask.rb` | claude's pop-up UI: one JSON file per prompt, answered by the browser |
| `bin/mcp-ui` | the tools claude gets — `ask_user`, `show_page`, `ask_result`, `send_notification` |
| `bin/screenshot`, `bin/record` | claude's eyes: headless Chrome for stills, Xvfb + ffmpeg for video |
| `config/skills/` | skills symlinked into `~/.claude/skills` at session start |
| `app/channels/terminal_channel.rb` | PTY ↔ ActionCable bridge (`tmux attach`), base64 frames, signed-token auth |
| `app/channels/mic_channel.rb` | browser mic → the FIFO claude's `/voice` records from |
| `app/views/terminal/show.html.erb` | the product: terminal + 🎤 + TRY IT + PAGES |
| `config/claude-brief.md` | claude's briefing — voice, publish dir, kamal settings, env |
| `config/routes.rb` | root, `/start`, the `/ui` static mount, the Caddy TLS gate |

### Lifecycle

**First run.** `/` redirects to `/start` while claude has no credentials, or
while the app folder is empty and nothing has been launched yet. `/start`
launches a `login` tmux session running plain `claude` (which offers its
sign-in flow) and scrapes the sign-in URL out of the pane — the TUI hard-wraps
it across real newlines and tmux's mouse mode swallows selections, so it can't
be copied by hand. Picking a starter POSTs to `/start`, which turns the choice
into a first prompt and launches the agent.

**Launch.** `Agent.ensure!` creates the tmux session (env: every
`APPSMOOTHLY_*` var plus `PORT`/`BINDING`, so the brief can talk about them by
name), styles it, and types:

    claude <flags> --continue || claude <flags> "<first prompt>"

`--continue` resumes the conversation after a reboot (claude keys history on
the working directory); on a box that has never run it, that exits non-zero and
the first prompt runs instead. `test/models/agent_test.rb` runs that line for
real against a fake claude.

**Staying available.** Every page load calls `ensure!`. If the session is gone
it's recreated; if the user quit claude and left a shell behind
(`at_a_shell?` — 10s grace, since claude's process title is its *version
number*, never "claude") it's restarted in place.

**Terminal.** The page mints a signed token naming the tmux session;
`TerminalChannel` `PTY.spawn`s `tmux attach-session`, streams output
base64-encoded (PTY bytes aren't valid JSON/UTF-8), writes input/resizes back.
Closing the tab detaches (HUP), never kills.

**Publishing.** `/ui` is a `Rack::Static` mount rooted at `~/public`
(`APPSMOOTHLY_PUBLISH_DIR`). Claude writes or symlinks HTML there and hands the
user a link; `index.html` is its home page, behind the PAGES button. Path
traversal is blocked by Rack; symlinks are followed on purpose.

### CI is local

There is no hosted runner. `config/ci.rb` is the build, `.githooks/pre-push`
runs it before anything reaches the remote (`bin/setup` points git at the hooks
— a fresh clone needs that once), and `gh signoff` sets the green commit status
GitHub would otherwise be waiting on. Install it once with
`gh extension install basecamp/gh-signoff`.

A status can only attach to a commit GitHub already has, so `bin/ci` signs off
only when HEAD is on a remote branch. `bin/ship` is `git push` (checks run in
the hook) followed by the signoff. `--no-verify` skips the gate if you truly
must.

### Gotchas (learned the hard way — don't relearn them)

- **Bundler env leaks into tmux.** The tmux server inherits the factory's
  BUNDLE_GEMFILE/RUBYOPT/GEM_* — `bundle`/`rails new` in the session would use
  the factory's bundle. `Factory.clean_tmux!` strips them globally
  (`tmux set-environment -g -r`) before any spawn. Keep calling it.
- **claude's process title is its version number** (e.g. "2.1.200"), not
  "claude" — that's why `at_a_shell?` detects the *absence* of a shell instead.
- **Turbo Drive is disabled globally** (`application.js`): body swaps would
  re-run the terminal module script and leak a live tmux attach per navigation.
- **xterm FitAddon** subtracts padding from the `.xterm` element, not its
  container — padding lives on `.xterm` in the CSS or the last row clips.
- **tmux mouse mode** is set per session (`Agent.style`) — without it xterm
  turns wheel scrolling into arrow keys (shell history).
- **Terminal copy is OSC 52, not browser selection.** Mouse mode means a drag
  selects in *tmux*, which copies and emits OSC 52 — xterm core silently drops
  it, so `shared/_terminal` registers a handler that writes it to the browser
  clipboard. `set-clipboard on` additionally lets apps inside tmux set it
  (claude's "c to copy"). Don't remove either half or copying dies silently.
- **`=name` targets only work for session commands** (`has-session`,
  `kill-session`) — pane-target commands like `capture-pane` reject them.
- **tailwind v4 watcher exits without a TTY**, killing foreman/`bin/dev` —
  headless contexts must use `tailwindcss:build` + `rails server`.
- **`rails server` honors PORT and BINDING env** — that's how the fixed 3100
  and 0.0.0.0 binding reach the app's dev server without flags.
- ActiveRecord is still installed (Rails default plumbing, solid_cache/queue/
  cable) but the app has zero tables of its own. Deliberate: ripping it out
  would touch the Gemfile, Dockerfile, bin/setup and buy nothing.

## Security notes

- On provisioned boxes the factory binds loopback; Caddy + Authelia (email
  login, passkeys) are the only way in — for the terminal, for `/ui`, and for
  app previews alike.
- Cable access requires a signed per-session token minted by the page — the
  websocket endpoint can't be driven directly.
- `/ui` serves whatever is in the publish dir on the factory's own origin.
  Claude writes those pages, and it already has a shell, so this adds no
  authority — but don't have it serve pages that pull in third-party scripts.
  Moving `/ui` to its own subdomain (a Caddy `file_server` block + one more
  entry in the on-demand-TLS allowlist) is the isolation upgrade path.
- The terminal is a real shell on the box. Treat access accordingly.
