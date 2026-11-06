#!/usr/bin/env python3
"""The smallest server the App can talk to. Standard library only.

    python3 server/demo_server.py            # listens on 0.0.0.0:8787

    GET  /status?wait=20                     # the App's long poll; answers at once on change, else after wait s
    POST /island  {"state":"happy","line":"在呢。"}       # what the island shows (state = a sprite name)
    POST /island  {"hide":true}                           # end the activity
    POST /say     {"text":"吃饭了吗","title":"demo"}       # a message → local notification on the phone

    curl -X POST localhost:8787/say -d '{"text":"hello"}'
"""
import json
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOCK = threading.Condition()
STATE = {"island": {"state": "calm", "line": "在呢。", "hide": False}, "messages": [], "version": 0}
MAX_WAIT = 25
KEEP = 50


def bump():
    STATE["version"] += 1
    LOCK.notify_all()


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            parsed = json.loads(raw or b"{}")
        except ValueError:
            return None
        return parsed if isinstance(parsed, dict) else None

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/status":
            return self._json(404, {"error": "not found"})
        wait = min(MAX_WAIT, max(0, int((parse_qs(url.query).get("wait") or ["0"])[0] or 0)))
        presence = self.headers.get("X-Presence", "?")
        standby = self.headers.get("X-Standby", "?")
        with LOCK:
            seen = STATE["version"]
            deadline = time.monotonic() + wait
            while STATE["version"] == seen and time.monotonic() < deadline:
                LOCK.wait(deadline - time.monotonic())
            body = {"island": dict(STATE["island"]), "messages": list(STATE["messages"])}
        print(f"poll from {presence} standby={standby} → {body['island']['state']} {len(body['messages'])} msgs", flush=True)
        self._json(200, body)

    def do_POST(self):
        body = self._body()
        if body is None:
            return self._json(400, {"error": "body must be a JSON object"})
        with LOCK:
            if self.path == "/island":
                for key in ("state", "line"):
                    if isinstance(body.get(key), str) and body[key]:
                        STATE["island"][key] = body[key][:30]
                if "hide" in body:
                    STATE["island"]["hide"] = bool(body["hide"])
                bump()
                return self._json(200, STATE["island"])
            if self.path == "/say":
                text = body.get("text")
                if not isinstance(text, str) or not text.strip():
                    return self._json(400, {"error": "text required"})
                message = {"id": uuid.uuid4().hex[:12], "text": text.strip()[:200]}
                if isinstance(body.get("title"), str) and body["title"]:
                    message["title"] = body["title"][:24]
                STATE["messages"].append(message)
                del STATE["messages"][:-KEEP]
                bump()
                return self._json(200, message)
        self._json(404, {"error": "not found"})

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8787), Handler)
    print("demo server on http://0.0.0.0:8787  (Ctrl-C to stop)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
