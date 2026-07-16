#!/bin/bash
# Rails App Factory — development VPS bootstrap (Ubuntu 22.04 / 24.04).
# Run as a non-root user with sudo:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOURUSER/rails-app-factory/main/setup.sh)
# Override the repo with: FACTORY_REPO=https://github.com/you/yourfork.git
set -euo pipefail

RUBY_VERSION=3.4.7
LITESTREAM_VERSION=0.3.13
FACTORY_REPO="${FACTORY_REPO:-https://github.com/YOURUSER/rails-app-factory.git}"

echo "=> system packages"
sudo apt-get update -y
sudo apt-get install -y git tmux sqlite3 curl build-essential pkg-config autoconf bison \
  libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgmp-dev

echo "=> tailscale (the factory is only reachable through it)"
if ! command -v tailscale >/dev/null; then curl -fsSL https://tailscale.com/install.sh | sh; fi
sudo tailscale up

echo "=> docker (kamal builds images here)"
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
sudo usermod -aG docker "$USER"

echo "=> github cli (Claude uses it to push code and open pull requests)"
if ! command -v gh >/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
fi

echo "=> litestream (backup status + pulling prod snapshots)"
if ! command -v litestream >/dev/null; then
  curl -fsSL -o /tmp/litestream.deb "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-amd64.deb"
  sudo dpkg -i /tmp/litestream.deb
fi

echo "=> ruby ${RUBY_VERSION} via rbenv"
if [ ! -d "$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
  git clone https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
  printf 'export PATH="$HOME/.rbenv/bin:$PATH"\neval "$(rbenv init - bash)"\n' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
rbenv install -s "$RUBY_VERSION"
rbenv global "$RUBY_VERSION"
gem install rails --no-document

echo "=> claude code"
if ! command -v claude >/dev/null; then curl -fsSL https://claude.ai/install.sh | bash; fi

echo "=> ssh key (read access to private git repos, pushing from sessions)"
[ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"

echo "=> the factory itself"
if [ -d "$HOME/rails-app-factory" ]; then
  git -C "$HOME/rails-app-factory" pull --ff-only
else
  git clone "$FACTORY_REPO" "$HOME/rails-app-factory"
fi
cd "$HOME/rails-app-factory"
bundle install
bin/rails db:prepare
bin/rails tailwindcss:build
mkdir -p "$HOME/projects"
touch .env
# The factory binds to the tailscale IP only (see the systemd unit below), so the
# private network is the auth boundary. Acknowledge that so it serves without a
# password; set RAILS_APP_FACTORY_PASSWORD in .env instead if you want a login.
grep -q '^RAF_TRUST_NETWORK=' .env || echo 'RAF_TRUST_NETWORK=1' >> .env

TS_IP="$(tailscale ip -4)"
echo "=> systemd service (bound to the tailscale IP only — invisible from the public internet)"
sudo tee /etc/systemd/system/rails-app-factory.service >/dev/null <<UNIT
[Unit]
Description=Rails App Factory
After=network-online.target tailscaled.service

[Service]
User=$USER
WorkingDirectory=$HOME/rails-app-factory
Environment=RAF_PROJECTS_DIR=$HOME/projects
EnvironmentFile=-$HOME/rails-app-factory/.env
ExecStart=$HOME/.rbenv/shims/ruby bin/rails server -b $TS_IP -p 3000
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now rails-app-factory

echo
echo "=============================================================="
echo " Factory running:  http://$TS_IP:3000/start  (tailscale devices only)"
echo
echo " Open that in your browser — the Get started page signs Claude and"
echo " GitHub in, right from the browser. No need to SSH back in."
echo
echo " Production servers later: order a VPS, SSH in once and run"
echo "   curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --ssh"
echo " — the factory handles the rest (kamal + its local registry)."
echo "=============================================================="
