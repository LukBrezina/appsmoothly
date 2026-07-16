# Rails App Factory

Your personal Rails PaaS on two cheap VPSes. A **development VPS** runs the
factory: create or connect Rails apps, drive Claude Code on them in browser
terminals (each session in its own git worktree with a live preview), then
deploy to a **production VPS** with Kamal — with continuous, undeletable S3
backups and point-in-time restore.

Status: dev flow is verified end-to-end locally. Production/backup flow is
implemented and unit-tested but has not yet run against a real VPS/bucket —
see [Verified vs untested](#verified-vs-untested).

---

## User guide

### Get started (development VPS)

1. Order any Ubuntu 22.04/24.04 VPS (2GB+ RAM — it builds Docker images).
2. Have a [tailscale](https://tailscale.com) account (free tier is fine).
3. SSH in as a sudo-capable user and run:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/YOURUSER/rails-app-factory/main/setup.sh)
```

The script installs tailscale, docker, ruby (rbenv), tmux, litestream, the
GitHub CLI and Claude Code, generates an SSH key, then starts the factory as a
systemd service **bound to the tailscale IP only** — it does not exist on the
public internet. Open `http://<tailscale-ip>:3000` from any tailscale device:
the **Get started** page signs Claude and GitHub in from browser terminals —
no need to SSH back in. Optional extra gate: `RAILS_APP_FACTORY_PASSWORD` in
`.env` enables HTTP basic auth.

**Updating**: `cd ~/rails-app-factory && bin/update` (pull, migrate, restart).

**Local development of the factory itself**:
`bin/setup && RAF_PROJECTS_DIR=~/somewhere bin/dev` (or
`bin/rails tailwindcss:build && bin/rails server` — see gotcha about the
tailwind watcher below).

### Apps

- **+ ADD APP** with just a name runs `rails new <name> --css=tailwind` in a
  visible tmux session and installs the factory plumbing as the first commit.
- Give a **git address** instead and the factory clones your existing app.
  Private GitHub repos work over https once GitHub is connected on the Get
  started page (`gh auth setup-git` wires git through gh's credentials);
  other hosts: use the ssh address and add the machine's key (shown on the
  page) as a deploy key.
- Type any title ("My new app") — the technical name (`my-new-app`) is
  derived automatically and used for folders, URLs and tmux.

### Sessions

A session = one git worktree + one tmux session + one Claude + one dev server
on a random port. Launch from the SESSIONS page; the browser terminal attaches
to tmux, the TRY IT link opens the app's test version over tailscale. Closing
the tab detaches; Claude keeps working. Ending a session runs the app's
teardown hook, removes the worktree, and keeps the `raf/<name>` branch so all
committed work stays reachable.

Emails the test app "sends" are captured to files (they never reach real
people) and shown in the factory's own style behind the **INBOX** link next to
TRY IT. To also forward a captured email to a real address from its preview,
set `RAF_SMTP_ADDRESS`, `RAF_SMTP_USER_NAME`, `RAF_SMTP_PASSWORD` (optionally
`RAF_SMTP_PORT`, `RAF_SMTP_FROM`) in the factory's `.env` — any SMTP relay.

### Hooks — bring your own app

Each app tells the factory how to run it in `config/rails_app_factory.rb` —
plain Ruby, executed in the session's workspace by the factory's `bin/hook`
runner. `sh "..."` runs a shell command and stops on failure; `app`, `session`
and `port` identify the workspace; any Ruby works.

```ruby
setup do                     # session start, in the fresh workspace
  sh "bundle install"
  db = "#{app}_dev_#{session}"
  system "createdb", db      # fine if it already exists
  File.write ".env", "DATABASE_URL=postgres://localhost/#{db}\n"
  sh "bin/rails db:prepare"
end

server do                    # the test server — must listen on ENV["PORT"]
  sh "bin/dev"
end

teardown do                  # session end, before the workspace is deleted
  sh "dropdb --if-exists #{app}_dev_#{session}"
end
```

Without the file (or a missing block) the fallback convention applies:
`bin/setup-worktree` (if executable) → `bin/dev`, and `bin/teardown-worktree`
on session end. Factory-created apps get the config file + `bin/setup-worktree`
(copies master.key/.env from the main checkout, bundle, db:prepare) committed
automatically.

### Going live (production)

No registry account, no SSH keys — Kamal uses its built-in local registry
(`localhost:5555`, tunnelled over SSH) and deploys over your tailnet.

1. Order a fresh Ubuntu VPS, SSH in once:
   `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --ssh`
   One-time tailnet setting: change the ssh ACL rule's `"action": "check"` to
   `"accept"` so unattended deploys don't re-prompt.
2. On the GO LIVE page: enter the server's tailscale name + the domain; create
   the shown A record (pointing at the server's *public* IP). Wait for DNS —
   Let's Encrypt needs it.
3. Deploy. First run is `kamal setup` (installs Docker on the server),
   afterwards `kamal deploy`. The log streams into a live terminal session.
   Multiple apps can share one production server.

### Backups

Recommended storage: a Google Cloud Storage bucket with a **retention policy**
(e.g. 30 days, lockable) — nothing can delete or overwrite objects before they
age out, regardless of credentials. Service account with only Object Creator +
Viewer, HMAC key (Interoperability settings), endpoint
`https://storage.googleapis.com`. Steps are on the BACKUPS page. Any
S3-compatible store works.

- **Database**: Litestream streams the production SQLite WAL to the bucket
  every 30 seconds (runs as a Kamal accessory sharing the app's storage
  volume). Continuous history → restore to any second.
- **Attachments**: production Active Storage writes to the same bucket, so
  they share the same undeletability.
- **Rewind**: pick a UTC timestamp on the BACKUPS page — stops the app,
  restores the DBs on the prod volume, boots, restarts replication, all in a
  watchable terminal session.
- **Copy live data into a session**: one click; runs `bin/pull-prod-data` in a
  new tmux window of that session. Session gets `S3_*` env so pulled data can
  serve its attachments straight from the bucket.
- Litestream backups are SQLite-specific; connected Postgres apps need their
  own backup story for now. Also enable your VPS provider's machine snapshots.

---

## Architecture (for whoever hacks on this next)

### Big picture

- The factory is a vanilla Rails 8.1 app (Tailwind v4, importmap, SQLite).
- **SQLite stores only the `apps` table.** Sessions have no rows — **tmux is
  the source of truth**; the session list is parsed from
  `tmux list-panes -a` on every request, and per-session state (PORT) lives in
  the tmux session environment (`tmux show-environment`).
- Everything long-running happens **inside visible tmux sessions** the browser
  can attach to: app creation, deploys, restores. One pattern everywhere.

### Naming conventions (load-bearing)

- tmux session name = `<app>--<session>`. Names are validated by
  `/\A\w+(?:-\w+)*\z/` (Factory.safe_name / App validations), which makes a
  literal `--` impossible inside a name, so the split is unambiguous.
- Users type free-text titles; `App#title` is displayed, `App#name` (slugged
  via `parameterize`) is used for paths/URLs/tmux. Session input is
  parameterized in the controller.
- Reserved session names: `setup` (app creation), `deploy`, `restore` —
  they're ordinary tmux sessions the factory drives, and they show up in the
  UI like any session. Reserved app names: see `App::RESERVED_NAMES` (route
  collisions; `factory` is reserved because onboarding uses
  `factory--claude-login`/`factory--github-login` tmux sessions).
- Worktrees live at `<projects>/.worktrees/<app>--<session>` on branch
  `raf/<session>`. Removal keeps the branch.

### Key files

| file | role |
|---|---|
| `app/models/app.rb` | AR model; title→name derivation, prod/backup config columns, `s3_env`/`litestream_env` |
| `app/models/tmux_session.rb` | PORO; list/launch/kill sessions, tmux styling (mouse on + pastel status bar), worktree paths |
| `app/models/production.rb` | writes `config/deploy.yml` + `.kamal/secrets` into the app repo, commits, runs kamal in `<app>--deploy` |
| `app/models/backup.rb` | restore/pull launchers, `litestream generations` status |
| `app/models/mailbox.rb` | reads a session worktree's `tmp/mails` (RafMailbox delivery, installed by create-app), renders/forwards captured email |
| `app/models/onboarding.rb` | Get started page (`/start`): checks Claude/gh sign-in, launches `factory--claude-login`/`factory--github-login` tmux sessions for the browser-terminal logins |
| `app/channels/terminal_channel.rb` | PTY ↔ ActionCable bridge (`tmux attach`), base64 frames, signed-token auth |
| `bin/hook` | plain-Ruby hook runner (setup/server/teardown DSL) — executed with the *app's* Ruby, keep it old-Ruby-compatible |
| `bin/create-app` | runs in `<app>--setup` tmux: `rails new` + plumbing, or `git clone` for connected apps |
| `bin/update`, `setup.sh` | factory update / dev-VPS bootstrap (systemd unit bound to tailscale IP) |
| `lib/factory.rb` | projects dir, safe_name, free_port, tailscale DNS name, message verifier, `clean_tmux!` |
| `app/views/layouts/application.html.erb` | header app switcher, sidebar, flash, 4s JSON poll |
| `app/assets/tailwind/application.css` | design tokens (`@theme`) + the few custom pieces (clip-tag, dots, cmd chips) |

### Session lifecycle

Launch (`TmuxSession.launch`): pick a free port (bind :0, close) → `git
worktree add -b raf/<name>` (falls back to reattach if the branch exists) →
`Factory.clean_tmux!` → `tmux new-session -d` with env `PORT`,
`BINDING=0.0.0.0`, `RAF_APP`, `RAF_SESSION` (+ `S3_*` when backups are
configured) → window 0 "claude" runs the agent, window 1 "server" runs
`bin/hook setup server`.

Kill (`TmuxSession.kill`): read PORT from tmux env → kill session → run
`bin/hook teardown` synchronously (chdir worktree, RAF_* env) → `git worktree
remove --force`.

Browser terminal: `sessions#show` mints a signed token
(`Rails.application.message_verifier`) naming the tmux session; the client
subscribes to `TerminalChannel` with it; the channel `PTY.spawn`s
`tmux attach-session`, streams output base64-encoded (PTY bytes aren't valid
JSON/UTF-8), and writes input/resizes back. Closing = detach (HUP), never kill.

Live UI: the layout polls `/:app/sessions.json` every 4s and patches
`[data-dot] [data-title] [data-cmd] [data-preview]` under any
`[data-session-name]` element. Claude's task titles arrive via tmux
`pane_title` (Claude sets the terminal title with OSC escapes).

### Deploy & backups internals

- `Production.deploy_yaml` builds deploy.yml as a string (YAML-validated in
  tests): kamal local registry (`registry: server: localhost:5555`, plain
  image name, no creds), `servers: [prod_server]` (a tailscale name/IP),
  proxy ssl + host, storage volume, and — when backups are configured — a
  litestream accessory sharing `<app>_storage` with `config/litestream.yml`
  mounted. `.kamal/secrets` resolves everything from the deploy session's env;
  the file itself holds no secrets. Both files are committed before deploy
  because **kamal builds from git HEAD**.
- First deploy = `kamal setup`, tracked via `apps.deployed_at`; later =
  `kamal deploy`. Env (S3 keys) is injected into the tmux session via `-e`.
- Restore: `bin/restore-prod TIMESTAMP` (installed into apps by create-app)
  stops accessory+app, docker-runs litestream restore against the volume on
  the server via `kamal server exec`, boots, reboots the accessory. Runs in
  `<app>--restore` tmux.
- Backup status: the factory shells out to local `litestream generations` with
  the app's env (6s timeout, missing-binary handled).

### Gotchas (learned the hard way — don't relearn them)

- **Bundler env leaks into tmux.** The tmux server inherits the factory's
  BUNDLE_GEMFILE/RUBYOPT/GEM_* — `rails new`/`bundle` in sessions would use
  the factory's bundle. `Factory.clean_tmux!` strips them globally
  (`tmux set-environment -g -r`) before any spawn. Keep calling it.
- **claude's process title is its version number** (e.g. "2.1.200"), not
  "claude" — `TmuxSession#claude?` matches `/\A\d+(\.\d+)+\z/`.
- **Turbo Drive is disabled globally** (`application.js`): body swaps would
  re-run the terminal module script and leak a live tmux attach per
  navigation. Confirms are plain `onsubmit`, not `turbo_confirm`.
- **xterm FitAddon** subtracts padding from the `.xterm` element, not its
  container — padding lives on `.xterm` in the CSS or the last row clips.
- **tmux mouse mode** is set per factory session (`TmuxSession.style`) —
  without it xterm turns wheel scrolling into arrow keys (shell history).
  Style also sets a pastel status bar; sessions are created detached, styled,
  then used.
- **tailwind v4 watcher exits without a TTY**, killing foreman/`bin/dev` —
  headless contexts must use `tailwindcss:build` + `rails server` (setup.sh's
  systemd unit does exactly that).
- **`rails server` honors PORT and BINDING env** — that's how per-session
  ports and 0.0.0.0 binding reach `bin/dev` without flags.
- Dev-mode host authorization: apps get a `config.hosts << /.+\.ts\.net/`
  initializer (create-app), the factory has the same in development.rb.
- `bin/hook` runs under the app's Ruby (rbenv shim per worktree) — no modern
  Ruby syntax in that file.
- The UI voice is deliberately non-technical (target user: hasn't coded in
  years). Glossary in use: deploy→"go live", restore→"rewind", worktree→
  "private workspace", attached→"open in a browser". Keep it.

### Verified vs untested

Verified end-to-end in a real browser (Chrome driving the actual UI):
app creation via `rails new` watched live; session launch (worktree + claude +
dev server on a random port); terminal input/output both directions; preview
URL serving; detach-on-close; kill removing the worktree and keeping the
branch; wheel scrollback; hook runner (subprocess tests).

Implemented but **not yet run against real infrastructure**: `kamal setup/
deploy` (incl. the tailscale-SSH + local-registry path), litestream against a
real GCS bucket, `bin/restore-prod` (its nested quoting through `kamal server
exec` is the most likely thing to need a fix), `setup.sh` on a fresh Ubuntu
box, the Get started sign-in flows (`claude` login / `gh auth login` inside
their tmux sessions), and the `git clone` connect flow for private repos.

## Security notes

- The factory and every terminal in it are reachable only over tailscale
  (systemd binds to the tailscale IP); optional HTTP basic auth on top.
- Cable access requires a signed per-session token minted by the page — the
  websocket endpoint can't be driven directly.
- S3 credentials are plain columns in the factory's SQLite (single-user,
  tailscale-only box); the deny-delete/retention bucket is the real backstop —
  even leaked keys can't destroy history.
- Terminal sessions are shells on the dev VPS. Treat tailnet access
  accordingly.
