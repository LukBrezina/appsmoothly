#!/usr/bin/env python3
"""Campfire <-> Claude Code bridge.

Receives Campfire bot webhooks (bot @mentioned in a room, or any message in
a direct room with the bot), runs `claude -p` headless on this machine, and
posts the result back to the room via Campfire's bot message API.

Stdlib only. Config comes from environment variables (see config.env):
  BRIDGE_SECRET   random path segment the webhook URL must contain
  LISTEN_ADDR     address to bind (docker network gateway; not tailnet-reachable)
  LISTEN_PORT
  CAMPFIRE_BASE   where to POST bot replies (kamal-proxy on localhost)
  CLAUDE_BIN      absolute path to the claude CLI
  WORKDIR         directory claude runs in
  SESSIONS_FILE   JSON file mapping room id -> claude session id
"""

import json
import html
import os
import re
import subprocess
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SECRET = os.environ["BRIDGE_SECRET"]
LISTEN_ADDR = os.environ.get("LISTEN_ADDR", "172.18.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "4488"))
CAMPFIRE_BASE = os.environ.get("CAMPFIRE_BASE", "http://127.0.0.1:8080").rstrip("/")
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
WORKDIR = os.environ.get("WORKDIR", os.path.expanduser("~/work/panter"))
SESSIONS_FILE = os.environ.get(
    "SESSIONS_FILE", os.path.expanduser("~/.local/state/claude-bot/sessions.json")
)
CLAUDE_TIMEOUT = int(os.environ.get("CLAUDE_TIMEOUT", "1800"))
WORKING_NOTICE_AFTER = 20  # seconds before posting a "still working" note
MAX_REPLY_CHARS = 8000

FIRST_MESSAGE_PREAMBLE = """\
You are operating as "Claude", a chat bot inside Campfire (a chat app). Messages
you receive are chat messages from users; whatever you output is posted back to
the chat room as your reply. Keep replies conversational and reasonably short —
summaries over walls of text. Plain markdown is fine. You run on the user's own
machine with full permissions and may edit repositories, run commands, deploy,
push to git, etc. when asked. This conversation persists per room, so follow-up
messages may refer to earlier tasks.

Room messages sent between your invocations are included automatically under
"[Messages since your last reply]". If you need older room history, run:
  ~/services/claude-bot/history <room-id> [count]
which prints the room's last <count> messages (default 50). The room id is in
each message header.

"""

sessions_lock = threading.Lock()
room_locks: dict = {}
room_locks_guard = threading.Lock()


def log(*args):
    print(*args, flush=True)


def load_sessions():
    try:
        with open(SESSIONS_FILE) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
    # Migrate old schema where values were bare session-id strings
    return {k: (v if isinstance(v, dict) else {"session": v}) for k, v in data.items()}


def update_room_state(room_id, **fields):
    with sessions_lock:
        sessions = load_sessions()
        sessions.setdefault(str(room_id), {}).update(fields)
        os.makedirs(os.path.dirname(SESSIONS_FILE), exist_ok=True)
        with open(SESSIONS_FILE, "w") as f:
            json.dump(sessions, f, indent=2)


def room_lock(room_id):
    with room_locks_guard:
        return room_locks.setdefault(str(room_id), threading.Lock())


def markdown_to_html(text):
    """Light markdown -> HTML for Campfire's rich-text messages."""
    out = []
    in_code = False
    for line in text.split("\n"):
        if line.strip().startswith("```"):
            out.append("</pre>" if in_code else "<pre>")
            in_code = not in_code
            continue
        if in_code:
            out.append(html.escape(line) + "\n")
            continue
        esc = html.escape(line)
        esc = re.sub(r"`([^`]+)`", r"<code>\1</code>", esc)
        esc = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", esc)
        esc = re.sub(r"^(#+)\s*(.*)$", r"<strong>\2</strong>", esc)
        esc = re.sub(r"^[-*]\s+", "• ", esc)
        out.append(esc + "<br>")
    if in_code:
        out.append("</pre>")
    return "".join(out)


def post_reply(room_path, text, as_html=True):
    body = markdown_to_html(text) if as_html else html.escape(text)
    req = urllib.request.Request(
        CAMPFIRE_BASE + room_path,
        data=body.encode("utf-8"),
        headers={"Content-Type": "text/html"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status


def fetch_recent_messages(room_path):
    """GET the room's most recent page of messages via the bot API."""
    req = urllib.request.Request(CAMPFIRE_BASE + room_path, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        if resp.status != 200:
            return []
        return json.loads(resp.read())


def unseen_context(room, trigger_message_id, last_seen):
    """Messages posted since the bot last ran, formatted for the prompt."""
    try:
        messages = fetch_recent_messages(room["path"])
    except Exception as e:
        log(f"room {room['id']}: history fetch failed: {e}")
        return ""
    unseen = [
        m for m in messages
        if m["id"] != trigger_message_id and (last_seen is None or m["id"] > last_seen)
    ]
    if not unseen:
        return ""
    lines = []
    for m in unseen[-25:]:
        name = (m.get("creator") or {}).get("name", "?")
        text = (m.get("body") or {}).get("plain_text", "").strip()
        if text:
            lines.append(f"{name}: {text}"[:500])
    if not lines:
        return ""
    return "[Messages since your last reply]\n" + "\n".join(lines) + "\n\n"


def run_claude(room_id, prompt, room_path=None):
    session_id = load_sessions().get(str(room_id), {}).get("session")
    cmd = [CLAUDE_BIN, "-p", "--output-format", "json", "--dangerously-skip-permissions"]
    if session_id:
        cmd += ["--resume", session_id]
    else:
        prompt = FIRST_MESSAGE_PREAMBLE + prompt
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(CLAUDE_BIN) + os.pathsep + env.get("PATH", "")
    # Let anything Claude runs answer in the room the request came from, rather
    # than guessing. ask-secret uses these.
    if room_path:
        env["CAMPFIRE_ROOM_PATH"] = room_path
    env["CAMPFIRE_BASE"] = CAMPFIRE_BASE
    proc = subprocess.run(
        cmd + [prompt], cwd=WORKDIR, env=env,
        capture_output=True, text=True, timeout=CLAUDE_TIMEOUT,
    )
    if proc.returncode != 0:
        # A stale/invalid session can make --resume fail; retry fresh once.
        if session_id:
            log(f"room {room_id}: resume failed ({proc.returncode}), retrying fresh session")
            update_room_state(room_id, session=None)
            return run_claude(room_id, prompt, room_path)
        raise RuntimeError(f"claude exited {proc.returncode}: {proc.stderr[-2000:]}")
    result = json.loads(proc.stdout)
    if result.get("session_id"):
        update_room_state(room_id, session=result["session_id"])
    return result.get("result") or "(no output)"


def handle_mention(payload):
    room = payload["room"]
    user = payload["user"]
    text = payload["message"]["body"]["plain"].strip()
    room_path = room["path"]
    message_id = payload["message"].get("id")
    log(f"room {room['id']} ({room['name']!r}) <- {user['name']!r}: {text[:120]!r}")

    last_seen = load_sessions().get(str(room["id"]), {}).get("last_seen")
    context = unseen_context(room, message_id, last_seen)
    if message_id:
        update_room_state(room["id"], last_seen=message_id)

    prompt = (
        context
        + f"[Campfire message from {user['name']} in room {room['name']!r} (room id {room['id']})]\n{text}"
    )

    done = threading.Event()

    def working_notice():
        if not done.wait(WORKING_NOTICE_AFTER):
            try:
                post_reply(room_path, "⏳ Working on it…", as_html=False)
            except Exception as e:
                log(f"room {room['id']}: working-notice post failed: {e}")

    threading.Thread(target=working_notice, daemon=True).start()

    try:
        with room_lock(room["id"]):
            reply = run_claude(room["id"], prompt, room_path)
    except subprocess.TimeoutExpired:
        reply = f"⚠️ I gave up after {CLAUDE_TIMEOUT // 60} minutes — the task ran too long."
    except Exception as e:
        reply = f"⚠️ Something went wrong on my end: {e}"
    finally:
        done.set()

    if len(reply) > MAX_REPLY_CHARS:
        reply = reply[:MAX_REPLY_CHARS] + "\n\n… (truncated)"
    try:
        status = post_reply(room_path, reply)
        log(f"room {room['id']} -> replied ({status}), {len(reply)} chars")
    except Exception as e:
        log(f"room {room['id']}: reply post FAILED: {e}")



# --- secret requests -------------------------------------------------------
# Claude asks for a value it must not see typed into chat; the human gets a
# one-time link and pastes it into a form. The value lands in a file the agent
# can read -- the point is keeping it out of the chat transcript, not hiding it
# from the agent.
#
# Served by this same process on purpose: it is already an HTTP server in the
# VM, so nothing new has to run.

SECRETS_DIR = os.path.expanduser("~/.secrets")
REQUESTS_FILE = os.path.expanduser("~/.local/state/claude-bot/secret-requests.json")
requests_lock = threading.Lock()


def _load_requests():
    try:
        with open(REQUESTS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_requests(data):
    os.makedirs(os.path.dirname(REQUESTS_FILE), exist_ok=True)
    tmp = REQUESTS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, REQUESTS_FILE)


def store_secret(name, value):
    os.makedirs(SECRETS_DIR, mode=0o700, exist_ok=True)
    path = os.path.join(SECRETS_DIR, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(value)
    return path


_PAGE = """<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
 body{{font:16px/1.5 system-ui,sans-serif;max-width:34rem;margin:3rem auto;padding:0 1rem;
      background:#fbfbfa;color:#1a1a19}}
 h1{{font-size:1.25rem;margin:0 0 .25rem}}
 p{{color:#5a5a57;margin:.25rem 0 1.25rem}}
 code{{background:#eee;padding:.1rem .3rem;border-radius:3px}}
 input,button{{font:inherit;width:100%;box-sizing:border-box;padding:.7rem;
      border:1px solid #ccc;border-radius:6px}}
 button{{margin-top:.75rem;background:#1a1a19;color:#fff;border:0;cursor:pointer}}
 .ok{{color:#0a7a35}} .bad{{color:#a11}}
</style>
<h1>{title}</h1><p>{sub}</p>{body}"""


def _page(title, sub, body=""):
    return _PAGE.format(title=html.escape(title), sub=sub, body=body).encode()


# --- end secret requests ---------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        m = re.fullmatch(r"/secret/([0-9a-f]{32})", self.path)
        if not m:
            self.send_response(404); self.end_headers(); return
        with requests_lock:
            req = _load_requests().get(m.group(1))
        if not req:
            self._html(410, _page("Link already used",
                                  "Ask Claude for a new one if you still need to send this."))
            return
        name = html.escape(req["name"])
        reason = html.escape(req.get("reason") or "")
        body = (f'<form method=post autocomplete=off>'
                f'<input name=value type=password placeholder="Paste value for {name}" '
                f'autofocus required>'
                f'<button>Save</button></form>')
        self._html(200, _page(f"Secret: {req['name']}",
                              reason or "Paste the value below. It is stored on this VM only "
                                        "and never appears in chat.", body))

    def do_POST(self):
        m = re.fullmatch(r"/secret/([0-9a-f]{32})", self.path)
        if m:
            token = m.group(1)
            with requests_lock:
                reqs = _load_requests()
                req = reqs.pop(token, None)
                if req:
                    _save_requests(reqs)
            if not req:
                self._html(410, _page("Link already used", "Nothing was saved.")); return
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode("utf-8", "replace")
            value = urllib.parse.parse_qs(raw).get("value", [""])[0]
            if not value:
                self._html(400, _page("Empty", "Nothing was saved.")); return
            path = store_secret(req["name"], value)
            log(f"secret '{req['name']}' stored ({len(value)} chars)")
            try:
                post_reply(req["room_path"],
                           f"Secret <code>{html.escape(req['name'])}</code> received and stored. "
                           f"It is not in this conversation.")
            except Exception as e:
                log(f"could not confirm in chat: {e}")
            self._html(200, _page("Saved", f"Stored as <code>{html.escape(path)}</code>. "
                                           "You can close this tab."))
            return

        if self.path != f"/hook/{SECRET}":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
            payload["room"]["path"] and payload["message"]["body"]["plain"]
        except Exception as e:
            log(f"bad payload: {e}")
            self.send_response(400)
            self.end_headers()
            return
        # Ack before Campfire's 7s webhook timeout; reply arrives via the bot API.
        self.send_response(204)
        self.end_headers()
        threading.Thread(target=handle_mention, args=(payload,), daemon=True).start()

    def _html(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    log(f"claude-bot bridge listening on {LISTEN_ADDR}:{LISTEN_PORT}, workdir {WORKDIR}")
    ThreadingHTTPServer((LISTEN_ADDR, LISTEN_PORT), Handler).serve_forever()
