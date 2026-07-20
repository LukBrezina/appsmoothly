# Appsmoothly

Your Rails PaaS in a box. One `tofu apply` provisions a customer VPS running
the factory behind Caddy + Authelia (email login, passkeys): create or connect
Rails apps, drive Claude Code on them in browser terminals (each session in
its own git worktree with a live preview), then go live on the same box with
Kamal — with continuous, undeletable S3 backups and point-in-time restore.

Status: dev flow is verified end-to-end locally. Production/backup flow is
implemented and unit-tested but has not yet run against a real VPS/bucket —
see [Verified vs untested](#verified-vs-untested).

---

## User guide

### Get started

Boxes are provisioned with OpenTofu: one `tofu apply` per customer creates the
VPS (cloud-init lays down Caddy, Authelia, docker, ruby, Claude Code and the
factory), a backup bucket that refuses deletion, and a Mailgun sending domain.
See [infra/README.md](infra/README.md) for the whole flow. Once the DNS
records from `tofu output dns_records` exist, open
`https://terminal.<customer>.appsmoothly.com`, sign in (admin password sits on
the box in `/root/authelia-admin-password.txt`), and use the **Get started**
page to sign Claude and GitHub in from browser terminals. Let people in with
`sudo add-user their@email.com` on the box.

**Updating**: `cd ~/appsmoothly && bin/update` (pull, migrate, restart).

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

On a provisioned box this is a button: server (`localhost` — the app runs on
this same machine behind Caddy) and web address are prefilled, backups are
already on. The steps below are the standalone two-VPS flow kept for
non-provisioned setups.

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

On a provisioned box backups need no setup: the bucket came with the machine
(`RAF_S3_*` env), streaming starts with the first deploy, and the BACKUPS page
is hidden from the menu (still reachable at `/<app>/backups`). Sessions carry
the `LITESTREAM_*` env, so you can simply ask Claude to list restore points
(`litestream snapshots`) or rewind (`bin/restore-prod <timestamp>`).

For standalone setups — recommended storage: a Google Cloud Storage bucket with a **retention policy**
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
- **SQLite stores `apps` and `sessions`.** A session row is its identity and
  lifecycle: it exists until the user ends it. **tmux is the runtime truth**:
  liveness, attached, current command, live title (parsed from
  `tmux list-panes -a` on every request), and PORT (tmux session environment,
  `tmux show-environment`). Row without tmux = *asleep* (e.g. after a server
  reboot); opening it relaunches tmux in the same worktree with
  `claude --continue`. Row + tmux + teardown hook + worktree are removed
  together, only on explicit kill.
- Everything long-running happens **inside visible tmux sessions** the browser
  can attach to: app creation, deploys, restores. One pattern everywhere.

### Naming conventions (load-bearing)

- tmux session name = `<app>--<session>`. Names are validated by
  `/\A\w+(?:-\w+)*\z/` (Factory.safe_name / App validations), which makes a
  literal `--` impossible inside a name, so the split is unambiguous.
- Users type free-text titles; `App#title` is displayed, `App#name` (slugged
  via `parameterize`) is used for paths/URLs/tmux. Sessions are created from a
  typed task ("What should Claude work on?"): `Session.slug_for` derives the
  stable slug (≤6 words, ≤48 chars, uniqued), the task becomes Claude's
  initial prompt, and Claude's own terminal title (OSC → `pane_title`)
  becomes the display name, persisted to the row as it changes.
- Reserved session names (`Session::RESERVED`): `setup` (app creation),
  `deploy`, `restore` — tmux sessions the factory drives. They get no rows;
  the session list wraps them as unsaved `Session`s while they run. Reserved
  app names: see `App::RESERVED_NAMES` (route
  collisions; `factory` is reserved because onboarding uses
  `factory--claude-login`/`factory--github-login` tmux sessions).
- Worktrees live at `<projects>/.worktrees/<app>--<session>` on branch
  `raf/<session>`. Removal keeps the branch.

### Key files

| file | role |
|---|---|
| `app/models/app.rb` | AR model; title→name derivation, prod/backup config columns, `s3_env`/`litestream_env` |
| `app/models/session.rb` | AR model; session identity/lifecycle, prompt→slug, merges rows with live tmux (`Session.for`), persists Claude's titles |
| `app/models/tmux_session.rb` | PORO, the runtime half; list/launch/kill tmux sessions, tmux styling (mouse on + pastel status bar), worktree paths |
| `app/models/production.rb` | writes `config/deploy.yml` + `.kamal/secrets` into the app repo, commits, runs kamal in `<app>--deploy` |
| `app/models/backup.rb` | restore/pull launchers, `litestream generations` status |
| `app/models/mailbox.rb` | reads a session worktree's `tmp/mails` (RafMailbox delivery, installed by create-app), renders/forwards captured email |
| `app/models/onboarding.rb` | Get started page (`/start`): checks Claude/gh sign-in, launches `factory--claude-login`/`factory--github-login` tmux sessions for the browser-terminal logins |
| `app/channels/terminal_channel.rb` | PTY ↔ ActionCable bridge (`tmux attach`), base64 frames, signed-token auth |
| `bin/hook` | plain-Ruby hook runner (setup/server/teardown DSL) — executed with the *app's* Ruby, keep it old-Ruby-compatible |
| `bin/create-app` | runs in `<app>--setup` tmux: `rails new` + plumbing, or `git clone` for connected apps |
| `bin/update` | update a running factory in place (pull, migrate, rebuild, restart) |
| `infra/` | OpenTofu: per-customer VPS (cloud-init: Caddy/Authelia/factory), backup bucket, Mailgun domain |
| `lib/factory.rb` | projects dir, safe_name, free_port, tailscale DNS name, message verifier, `clean_tmux!` |
| `app/views/layouts/application.html.erb` | header app switcher, sidebar, flash, 4s JSON poll |
| `app/assets/tailwind/application.css` | design tokens (`@theme`) + the few custom pieces (clip-tag, dots, cmd chips) |

### Session lifecycle

Create (`sessions#create`): slug the typed task → `Session` row →
`TmuxSession.launch(app, name, prompt:)`: pick a free port (bind :0, close) →
`git worktree add -b raf/<name>` (falls back to reattach if the branch
exists) → `Factory.clean_tmux!` → `tmux new-session -d` with env `PORT`,
`BINDING=0.0.0.0`, `RAF_APP`, `RAF_SESSION` (+ `S3_*` when backups are
configured) → window 0 "claude" runs the agent with the task as its prompt,
window 1 "server" runs `bin/hook setup server`.

Wake (`sessions#show` on an asleep row): `launch(..., resume: true)` — the
worktree survives reboots, both `git worktree add` calls fail harmlessly,
tmux restarts there and `claude --continue` picks the conversation back up
(Claude keys history on the working directory). Never triggered for
unpersisted names — a typo URL must not create workspaces.

Kill (`sessions#destroy`): `TmuxSession.kill` (read PORT from tmux env → kill
session → run `bin/hook teardown` synchronously (chdir worktree, RAF_* env) →
`git worktree remove --force`) → delete the row. Works the same when tmux is
already gone.

Browser terminal: `sessions#show` mints a signed token
(`Rails.application.message_verifier`) naming the tmux session; the client
subscribes to `TerminalChannel` with it; the channel `PTY.spawn`s
`tmux attach-session`, streams output base64-encoded (PTY bytes aren't valid
JSON/UTF-8), and writes input/resizes back. Closing = detach (HUP), never kill.

Live UI: the layout polls `/:app/sessions.json` every 4s and patches
`[data-dot] [data-title] [data-cmd] [data-preview]` under any
`[data-session-name]` element. Claude's task titles arrive via tmux
`pane_title` (Claude sets the terminal title with OSC escapes) and are
persisted onto the session row during listing (`Session#sync_title!`), so an
asleep session still shows the last name Claude gave it.

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
- **Terminal copy is OSC 52, not browser selection.** Mouse mode means a drag
  selects in *tmux*, which copies and emits OSC 52 — xterm core silently drops
  it, so `shared/_terminal` registers a handler that writes it to the browser
  clipboard (with an `execCommand` fallback for plain-http). `set-clipboard on`
  (in `style`) additionally lets apps inside tmux set it (claude's "c to
  copy"). Don't remove either half or copying dies silently again.
- **`=name` targets only work for session commands** (`has-session`,
  `kill-session`) — pane-target commands like `capture-pane` reject them;
  use the bare name.
- **tailwind v4 watcher exits without a TTY**, killing foreman/`bin/dev` —
  headless contexts must use `tailwindcss:build` + `rails server` (the
  provisioned box's systemd unit does exactly that).
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
deploy` (incl. the localhost + local-registry path), litestream against a
real GCS bucket, `bin/restore-prod` (its nested quoting through `kamal server
exec` is the most likely thing to need a fix), the whole `infra/` provisioning
path (tofu + cloud-init + Caddy + Authelia + Mailgun) on a fresh box, the Get
started sign-in flows (`claude` login / `gh auth login` inside their tmux
sessions), and the `git clone` connect flow for private repos.

## Security notes

- On provisioned boxes the factory binds to loopback; Caddy + Authelia
  (email login, passkeys) are the only way in, for the terminal and for
  session previews alike. Standalone factories should stay on a private
  network (tailscale) with optional HTTP basic auth on top.
- Cable access requires a signed per-session token minted by the page — the
  websocket endpoint can't be driven directly.
- S3 credentials are plain columns in the factory's SQLite (single-user,
  tailscale-only box); the deny-delete/retention bucket is the real backstop —
  even leaked keys can't destroy history.
- Terminal sessions are shells on the dev VPS. Treat tailnet access
  accordingly.
