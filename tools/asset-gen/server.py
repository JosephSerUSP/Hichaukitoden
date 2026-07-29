"""Local web UI for asset-gen.  python tools/asset-gen/server.py  (or runAssetGen.bat)

Standard library only -- no pip install, no build step, matching the editor's
"open a page and go" shape while staying a completely separate tool.

Every action the UI takes runs the real CLI through gen.main() with the argv it
would have typed, capturing stdout as the job log. There is deliberately no
second code path: if it works here it works in the terminal, and the log you see
is the log the CLI printed. Generation is slow, so it runs on a worker thread
behind a lock (one render at a time) and the page polls for progress.

Serves on 127.0.0.1 only. It writes into assets/ when you press Promote -- that
is the one action here with a side effect outside the staging area.
"""

import io
import json
import mimetypes
import os
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen as cli                                    # noqa: E402
from lib import classes, staging                     # noqa: E402

UI_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui")
PORT = int(os.environ.get("ASSET_GEN_PORT", "7801"))

_job_lock = threading.Lock()
_job = {"id": 0, "running": False, "log": "", "done": True, "ok": True, "run": None}


def _staging_root():
    return os.path.join(classes.ROOT, cli._config()["generate"]["stagingDir"])


class _LiveLog(io.TextIOBase):
    """Captured stdout that also publishes as it is written.

    A render takes minutes; buffering the whole run and only publishing at the
    end makes a working tool look hung. Each write lands in the job record
    immediately, so the page's poll always shows the newest line.
    """

    def __init__(self, sink=None):
        self.text = ""
        self.sink = sink

    def write(self, chunk):
        self.text += chunk
        if self.sink:
            self.sink(self.text)
        return len(chunk)

    def flush(self):
        pass


class _ThreadStdout(io.TextIOBase):
    """Routes stdout per thread.

    contextlib.redirect_stdout swaps sys.stdout for the whole PROCESS, so a
    long render would swallow the output of anything else running at the same
    time -- a Promote pressed mid-render would come back with an empty log. This
    proxy is installed once and hands each thread its own buffer, falling back
    to the real console for the server's own messages.
    """

    def __init__(self, real):
        self.real = real
        self.local = threading.local()

    def bind(self, buffer):
        self.local.buffer = buffer

    def release(self):
        self.local.buffer = None

    def write(self, chunk):
        buffer = getattr(self.local, "buffer", None)
        return buffer.write(chunk) if buffer is not None else self.real.write(chunk)

    def flush(self):
        self.real.flush()


_stdout = _ThreadStdout(sys.stdout)
sys.stdout = _stdout
sys.stderr = _stdout


def _run_cli(argv, sink=None):
    """Run one CLI command, returning (exit code, captured output)."""
    buffer = _LiveLog(sink)
    _stdout.bind(buffer)
    try:
        code = cli.main(argv)
    except SystemExit as err:                         # argparse bails this way
        code = err.code if isinstance(err.code, int) else 1
    except Exception as err:                          # noqa: BLE001 - surfaced in the log
        print(f"error: {err}")
        code = 1
    finally:
        _stdout.release()
    return code, buffer.text


def _job_worker(argv):
    code, output = _run_cli(argv, sink=lambda text: _job.update(log=text))
    latest = None
    try:
        latest = os.path.basename(staging.resolve_run(_staging_root(), "latest"))
    except Exception:                                 # noqa: BLE001 - no runs yet
        pass
    _job.update(running=False, done=True, ok=(code == 0), log=output, run=latest)
    _job_lock.release()


def _start_job(argv):
    if not _job_lock.acquire(blocking=False):
        return {"busy": True}
    _job.update(id=_job["id"] + 1, running=True, done=False, ok=True,
                log="working...\n", run=None)
    threading.Thread(target=_job_worker, args=(argv,), daemon=True).start()
    return {"jobId": _job["id"]}


def _runs_payload():
    root = _staging_root()
    out = []
    for name, manifest in staging.list_runs(root):
        out.append({
            "run": name,
            "class": manifest["class"],
            "name": manifest["name"],
            "target": f"{manifest['targetDir']}/{manifest['targetFile']}",
            "provider": manifest.get("provider", {}),
            "promoted": manifest.get("promoted", []),
            "variants": [
                {"index": v["index"], "url": f"/out/{name}/{v['file']}"}
                for v in manifest["variants"]
            ],
            "mtime": os.path.getmtime(os.path.join(root, name)),
        })
    out.sort(key=lambda r: r["mtime"], reverse=True)
    return out


def _classes_payload():
    reg = classes.registry()
    out = []
    for class_id, definition in reg["classes"].items():
        geom = definition["geometry"]
        size = geom.get("size")
        out.append({
            "id": class_id,
            "label": definition["label"],
            "dir": definition["dir"],
            "size": f"{size[0]}x{size[1]}" if size else "cell x frames",
            "cell": f"{geom['cell'][0]}x{geom['cell'][1]}",
            "frames": geom["frames"],
            "sheet": not size,
            "requestSize": definition.get("request", {}).get("size", "1024x1024"),
            "note": definition["note"],
            "wired": definition.get("engineWired", True),
        })
    cfg = cli._config()
    providers = []
    for pid, entry in cfg["providers"].items():
        providers.append({
            "id": pid,
            "label": entry["label"],
            "model": entry["model"],
            "quality": entry.get("quality"),
            "priced": entry["type"] == "openai-images",   # only this path takes `quality`
            "models": entry.get("models", []),
            "default": bool(entry.get("default")),
            "keyEnv": entry["apiKeyEnv"],
            "hasKey": bool(os.environ.get(entry["apiKeyEnv"], "").strip()),
        })
    return {"classes": out, "providers": providers,
            "variants": cfg["generate"]["variants"],
            "pricing": cfg.get("pricing", {})}


def _generate_argv(body):
    argv = ["generate", body["class"], body.get("name") or "unnamed"]
    argv.append(body.get("description") or "")
    for flag, key in (("--provider", "provider"), ("--model", "model"),
                      ("--quality", "quality"), ("--cell", "cell"),
                      ("--grid", "grid"), ("--extra", "extra")):
        if body.get(key):
            argv += [flag, str(body[key])]
    if body.get("frames"):
        argv += ["--frames", str(body["frames"])]
    if body.get("variants"):
        argv += ["--variants", str(body["variants"])]
    for token in (body.get("tokens") or "").split():
        argv += ["--token", token]
    for ref in body.get("refs") or []:
        argv += ["--ref", ref]
    if body.get("dryRun"):
        argv.append("--dry-run")
    return argv


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):                     # quiet; the UI is the log
        pass

    # -- helpers ----------------------------------------------------------
    def _send(self, code, body, content_type="application/json"):
        payload = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _static(self, rel):
        path = os.path.normpath(os.path.join(UI_DIR, rel.lstrip("/")))
        if not path.startswith(UI_DIR) or not os.path.isfile(path):
            return self._send(404, {"error": "not found"})
        with open(path, "rb") as handle:
            data = handle.read()
        self._send(200, data, mimetypes.guess_type(path)[0] or "text/plain")

    def _staged_file(self, rel):
        root = os.path.normpath(_staging_root())
        path = os.path.normpath(os.path.join(root, unquote(rel).lstrip("/")))
        if not path.startswith(root) or not os.path.isfile(path):
            return self._send(404, {"error": "not found"})
        with open(path, "rb") as handle:
            data = handle.read()
        self._send(200, data, mimetypes.guess_type(path)[0] or "application/octet-stream")

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    # -- routes -----------------------------------------------------------
    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self._static("index.html")
        if path.startswith("/out/"):
            return self._staged_file(path[len("/out/"):])
        if path == "/api/classes":
            return self._send(200, _classes_payload())
        if path == "/api/runs":
            return self._send(200, {"runs": _runs_payload()})
        if path == "/api/job":
            return self._send(200, dict(_job))
        return self._static(path)

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            body = self._body()
        except Exception:                             # noqa: BLE001
            return self._send(400, {"error": "bad JSON"})

        if path == "/api/key":
            # Held in this process's environment only -- never written to disk.
            env = body.get("env")
            value = (body.get("key") or "").strip()
            if not env:
                return self._send(400, {"error": "missing env"})
            if value:
                os.environ[env] = value
            else:
                os.environ.pop(env, None)
            return self._send(200, {"ok": True, "hasKey": bool(value)})

        if path == "/api/prompt":
            code, output = _run_cli(_generate_argv(dict(body, dryRun=True)))
            return self._send(200, {"ok": code == 0, "text": output})

        if path == "/api/generate":
            return self._send(200, _start_job(_generate_argv(body)))

        if path == "/api/reprocess":
            return self._send(200, _start_job(["reprocess", body.get("run") or "latest"]))

        if path == "/api/promote":
            argv = ["promote", body.get("run") or "latest",
                    "--variant", str(body.get("variant") or 1)]
            if body.get("rename"):
                argv += ["--rename", body["rename"]]
            if body.get("force"):
                argv.append("--force")
            code, output = _run_cli(argv)
            return self._send(200, {"ok": code == 0, "log": output})

        return self._send(404, {"error": "no such endpoint"})


def main():
    os.chdir(classes.ROOT)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"asset-gen UI: {url}")
    print("Ctrl+C to stop.")
    if not os.environ.get("ASSET_GEN_NO_BROWSER"):
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
