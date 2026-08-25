#!/usr/bin/env python3
"""Campfire <-> Claude Code bridge.

A chat room is a view onto a long-running Claude Code session, not a
request/response API. One `claude` process per room stays alive with streaming
input and output: messages you type are written to its stdin, and everything it
emits -- including subagent output -- is posted back as it happens.

That shape is what Claude Code already supports, so this file stays small. It
does not reconstruct conversation history, batch messages, resume per message,
or serialise turns: the session does all of that by existing.

Config comes from environment variables (see config.env):
  BRIDGE_SECRET   random path segment the webhook URL must contain
  LISTEN_ADDR     address to bind (docker network gateway; not tailnet-reachable)
  LISTEN_PORT
  CAMPFIRE_BASE   where to POST replies (kamal-proxy on localhost)
  CLAUDE_BIN      absolute path to the claude CLI
  WORKDIR         directory claude runs in
  SESSIONS_FILE   JSON file mapping room id -> claude session id
"""

import html
import json
import os
import re
import subprocess
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SECRET = os.environ["BRIDGE_SECRET"]
LISTEN_ADDR = os.environ.get("LISTEN_ADDR", "172.17.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "4488"))
CAMPFIRE_BASE = os.environ.get("CAMPFIRE_BASE", "http://127.0.0.1:8080").rstrip("/")
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
WORKDIR = os.environ.get("WORKDIR", "/home/appsmoothly")
SESSIONS_FILE = os.environ.get(
    "SESSIONS_FILE", os.path.expanduser("~/.local/state/claude-bot/sessions.json")
)
MAX_REPLY_CHARS = 8000

sessions_lock = threading.Lock()


def log(*args):
    print(*args, flush=True)


# --- chat -------------------------------------------------------------------

def markdown_to_html(text):
    """Light markdown -> HTML for Campfire's rich-text messages."""
    out, in_code = [], False
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
    if len(text) > MAX_REPLY_CHARS:
        text = text[:MAX_REPLY_CHARS] + "\n\n… (truncated)"
    body = markdown_to_html(text) if as_html else html.escape(text)
    req = urllib.request.Request(
        CAMPFIRE_BASE + room_path, data=body.encode("utf-8"),
        headers={"Content-Type": "text/html"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status


# --- sessions ---------------------------------------------------------------

def _load_ids():
    try:
        with open(SESSIONS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_id(room_id, session_id):
    with sessions_lock:
        data = _load_ids()
        data[str(room_id)] = session_id
        os.makedirs(os.path.dirname(SESSIONS_FILE), exist_ok=True)
        tmp = SESSIONS_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, SESSIONS_FILE)


class Session:
    """One long-running claude process for one room."""

    def __init__(self, room_id, room_path):
        self.room_id = room_id
        self.room_path = room_path
        self.proc = None
        self.lock = threading.Lock()

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self):
        cmd = [
            CLAUDE_BIN, "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            # Subagent output reaches the room too, so dispatching work is
            # visible rather than a silent gap.
            "--forward-subagent-text",
            "--permission-mode", "bypassPermissions",
        ]
        resume = _load_ids().get(str(self.room_id))
        if resume:
            cmd += ["--resume", resume]
        env = dict(os.environ)
        env["PATH"] = os.path.dirname(CLAUDE_BIN) + os.pathsep + env.get("PATH", "")
        env["CAMPFIRE_ROOM_PATH"] = self.room_path
        env["CAMPFIRE_BASE"] = CAMPFIRE_BASE
        try:
            self.proc = subprocess.Popen(
                cmd, cwd=WORKDIR, env=env, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
            )
        except Exception as e:
            log(f"room {self.room_id}: could not start claude: {e}")
            return False
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._drain_stderr, daemon=True).start()
        log(f"room {self.room_id}: session started{' (resumed)' if resume else ''}")
        return True

    def _drain_stderr(self):
        for line in self.proc.stderr:
            line = line.strip()
            if line:
                log(f"room {self.room_id} stderr: {line[:300]}")

    def _read(self):
        proc = self.proc
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            try:
                self._handle(event)
            except Exception as e:
                log(f"room {self.room_id}: event handling failed: {e}")
        code = proc.wait()
        log(f"room {self.room_id}: session exited ({code})")
        # A resume that cannot be replayed would fail on every restart; drop the
        # id so the next message starts a clean session instead of looping.
        if code != 0:
            _save_id(self.room_id, None)

    def _handle(self, event):
        kind = event.get("type")
        if kind == "system" and event.get("session_id"):
            _save_id(self.room_id, event["session_id"])
            return
        if kind == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "text" and block.get("text", "").strip():
                    post_reply(self.room_path, block["text"])
            return
        # "result" repeats the final assistant text, so posting it would double
        # every answer. Errors are the exception -- those are worth surfacing.
        if kind == "result" and event.get("is_error"):
            post_reply(self.room_path, f"⚠️ {event.get('result') or 'run failed'}")

    def send(self, text):
        with self.lock:
            if not self.alive() and not self.start():
                return False
            msg = {"type": "user", "message": {"role": "user",
                    "content": [{"type": "text", "text": text}]}}
            try:
                self.proc.stdin.write(json.dumps(msg) + "\n")
                self.proc.stdin.flush()
                return True
            except Exception as e:
                log(f"room {self.room_id}: write failed ({e}); restarting")
                self.proc = None
                if self.start():
                    self.proc.stdin.write(json.dumps(msg) + "\n")
                    self.proc.stdin.flush()
                    return True
                return False


_sessions = {}
_sessions_guard = threading.Lock()


def session_for(room_id, room_path):
    with _sessions_guard:
        s = _sessions.get(str(room_id))
        if s is None:
            s = _sessions[str(room_id)] = Session(room_id, room_path)
        s.room_path = room_path
        return s


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
    def _html(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

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
                f'autofocus required><button>Save</button></form>')
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
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
            room = payload["room"]
            text = payload["message"]["body"]["plain"].strip()
        except Exception as e:
            log(f"bad payload: {e}")
            self.send_response(400); self.end_headers(); return
        # Ack inside Campfire's 7s webhook timeout; the reply arrives later,
        # asynchronously, via the bot API.
        self.send_response(204); self.end_headers()
        who = (payload.get("user") or {}).get("name", "someone")
        log(f"room {room['id']} ({room['name']!r}) <- {who!r}: {text[:120]!r}")
        s = session_for(room["id"], room["path"])
        threading.Thread(target=s.send, args=(f"[{who} in #{room['name']}]\n{text}",),
                         daemon=True).start()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    log(f"claude-bot bridge listening on {LISTEN_ADDR}:{LISTEN_PORT}, workdir {WORKDIR}")
    ThreadingHTTPServer((LISTEN_ADDR, LISTEN_PORT), Handler).serve_forever()
