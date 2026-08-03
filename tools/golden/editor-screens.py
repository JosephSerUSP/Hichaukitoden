#!/usr/bin/env python3
"""G6 -- golden editor screenshot gate: capture and comparison.

G5 (tools/golden/screens.py) byte-compares the frames the *game* renders. The
editor is the other half of the project's surface area and had no gate at all:
G1 validates the data the editor writes, but nothing looked at the editor
itself, so a broken groupbox, a form that renders no fields, a modal that opens
empty, or a tab that throws before it paints were all invisible until a human
happened to open that exact tab.

This gate closes that hole the same way G5 does -- by driving the real editor
and byte-comparing pixels. It boots `tools/editor/server.js` on its own port,
drives a headless Chrome over the DevTools protocol through every tab and modal
state listed in STEPS, and compares each frame against tools/golden/editor-
screens/.

Read-only by construction: no step calls saveData(), and the server is started
in a child process whose only writes would come from a POST the harness never
sends. (tools/editor writes form edits straight through to data/*.json -- see
AGENTS.md -- so a gate that clicked Save would rewrite the campaign it is
supposed to be measuring.)

Determinism levers, all applied before the page's own scripts run:
  * fixed 1440x900 viewport at deviceScaleFactor 1, scrollbars hidden;
  * Math.random reseeded from a fixed LCG, Date/now frozen at a fixed epoch,
    so any id or timestamp the editor mints is stable run to run;
  * localStorage activeThemeId pinned to `classic` (studio.js otherwise
    restores whatever theme the last human session left behind);
  * transitions/animations/carets disabled via an injected stylesheet, and
    every step settles on document.fonts.ready plus two animation frames.

Like G5 this is a claim about one machine and one Chrome build, not about
cross-machine reproducibility. A font or Chrome update may legitimately shift
pixels; that is an owner-signed re-record, not a thing to paper over.

Usage:
    python tools/golden/editor-screens.py capture
    python tools/golden/editor-screens.py check
"""

import argparse
import base64
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

try:
    import websocket  # websocket-client
except ImportError:
    sys.exit("editor-screens.py: needs the `websocket-client` package "
             "(pip install websocket-client)")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF_DIR = os.path.join(ROOT, "tools", "golden", "editor-screens")
ACTUAL_DIR = os.path.join(ROOT, "tools", "golden", "editor-screens-actual")
SERVER_JS = os.path.join(ROOT, "tools", "editor", "server.js")

VIEWPORT = (1440, 900)
BOOT_TIMEOUT = 60.0
STEP_TIMEOUT = 30.0

CHROME_CANDIDATES = [
    os.environ.get("CHROME_PATH"),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
]

# ---------------------------------------------------------------------------
# The capture set.
#
# `js` runs in the page and may return a promise. `wait` is polled until it
# evaluates truthy -- prefer waiting on the thing the step is about to
# photograph over waiting on a clock. Every step starts from a closed-modal
# map editor (see RESET_JS), so steps are order-independent.
# ---------------------------------------------------------------------------

DB_TABS = [
    "actors", "items", "skills", "passives", "states", "elements", "roles",
    "animations", "shops", "commonEvents", "quests", "lore",
    "actionSequences", "troops", "terms", "system",
]

ENGINE_TABS = [
    "battleflow", "progression", "dungeon", "rendering", "fog",
    "effectTypes", "traitCodes", "metaKeys", "flows", "windows",
]

# Selecting the first row of a database tab's list box: the form panel is the
# half of the Database Manager worth photographing, and an unselected tab shows
# an empty one. Falls back silently on the list-less tabs (system/terms).
FIRST_EVENT_JS = """
    var ev = dbPayload.maps[0].events[0];
    openEventModal(ev.x, ev.y);
"""

SELECT_FIRST_ROW = """
    var row = document.querySelector('#db-item-list .list-item, #db-item-list li, #db-item-list > *');
    if (row) row.click();
"""


def build_steps():
    steps = [
        dict(path="map-editor/mode-event.png",
             js="switchMode('event');",
             wait="document.getElementById('tool-event-btn').classList.contains('active')"),
        dict(path="map-editor/mode-map.png",
             js="switchMode('map');",
             wait="document.getElementById('tool-map-btn').classList.contains('active')"),
        dict(path="map-editor/mode-light.png",
             js="switchMode('light');",
             wait="document.getElementById('tool-light-btn').classList.contains('active')"),
        dict(path="map-editor/mode-override.png",
             js="switchMode('override');",
             wait="document.getElementById('tool-override-btn').classList.contains('active')"),
        dict(path="map-editor/map-properties.png",
             js="openMapProperties();",
             wait="document.getElementById('map-properties-modal').classList.contains('active')"),
        # The first authored event of the first map, not an empty cell: opening
        # an empty cell photographs a blank new-event form, which says nothing
        # about whether pages, triggers and the command list still render.
        dict(path="map-editor/event-modal.png",
             js=FIRST_EVENT_JS,
             wait="document.getElementById('event-modal').classList.contains('active')"),
        dict(path="map-editor/command-selector.png",
             js=FIRST_EVENT_JS + " openCommandSelector('map', function () {});",
             wait="document.getElementById('cmd-selector-modal').classList.contains('active')"),
    ]

    for tab in DB_TABS:
        steps.append(dict(
            path="database/%s.png" % tab,
            js="openDatabaseModal(); setDbTab('%s');%s" % (tab, SELECT_FIRST_ROW),
            wait="document.getElementById('db-tab-%s').classList.contains('active')" % tab,
        ))

    for tab in ENGINE_TABS:
        steps.append(dict(
            path="engine/%s.png" % tab,
            js="openEngineModal(); setEngineTab('%s');" % tab,
            wait="document.getElementById('engine-tab-%s').classList.contains('active')"
                 " && document.getElementById('engine-form-panel').children.length > 0" % tab,
        ))

    steps += [
        dict(path="studio/preferences.png",
             js="openStudioModal();",
             wait="document.getElementById('studio-modal').classList.contains('active')"
                  " && document.getElementById('studio-theme-form-panel').children.length > 0"),
        # The tileset list arrives from /api/tilesets after the modal is up;
        # waiting only on the modal photographs an empty atlas.
        dict(path="tileset-studio/default.png",
             js="openTilesetStudioModal();",
             wait="document.getElementById('tileset-studio-modal').style.display !== 'none'"
                  " && document.getElementById('ts-select-tileset').options.length > 0"
                  " && document.getElementById('ts-atlas-canvas').width > 1"),
        dict(path="campaign-gen/default.png",
             js="openCampaignGenModal();",
             wait="document.getElementById('campaign-gen-modal').classList.contains('active')"
                  " && document.getElementById('cg-stage-strip').children.length > 0"),
        dict(path="icon-picker/default.png",
             js="openIconPicker(1, function() {});",
             wait="document.getElementById('icon-picker-modal').classList.contains('active')"
                  " && document.getElementById('icon-picker-grid').children.length > 0"),
    ]
    return steps


# Every modal closed, back to the default map editor view. Forced closes only:
# a step may have left a modal "dirty", and the confirm() a soft close would
# raise has no one to answer it in a headless browser.
RESET_JS = """
(function () {
    ['icon-picker-modal', 'asset-picker-modal', 'cmd-modal', 'cmd-selector-modal',
     'damage-popup-modal', 'max-modal', 'map-properties-modal', 'event-modal',
     'tileset-studio-modal', 'campaign-gen-modal', 'studio-modal', 'db-modal',
     'engine-modal', 'toast-modal'].forEach(function (id) {
        var el = document.getElementById(id);
        if (!el) return;
        el.classList.remove('active');
        if (el.style.display && el.style.display !== 'none') el.style.display = 'none';
    });
    ['map-context-menu', 'canvas-context-menu', 'cmd-context-menu'].forEach(function (id) {
        var el = document.getElementById(id);
        if (el) el.style.display = 'none';
    });
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    window.scrollTo(0, 0);
    // The editing mode is global state that outlives a modal close, and it
    // shows through every modal's backdrop. Without this, reordering STEPS
    // would silently change what the golden frames look like.
    switchMode('event');
    currentMapIndex = 0;
    loadActiveMap();
})();
"""

# Runs before any page script, on every document.
DETERMINISM_JS = r"""
(function () {
    var seed = 12345;
    Math.random = function () {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed / 0x7fffffff;
    };

    var FIXED = Date.UTC(2026, 0, 1, 0, 0, 0);
    var RealDate = Date;
    function FrozenDate(a, b, c, d, e, f, g) {
        if (!(this instanceof FrozenDate)) return new RealDate(FIXED).toString();
        if (arguments.length === 0) return new RealDate(FIXED);
        return new RealDate(a, b, c, d, e, f, g);
    }
    FrozenDate.prototype = RealDate.prototype;
    FrozenDate.now = function () { return FIXED; };
    FrozenDate.parse = RealDate.parse;
    FrozenDate.UTC = RealDate.UTC;
    Date = FrozenDate;

    try { localStorage.setItem('activeThemeId', 'classic'); } catch (e) {}

    // The editor uses confirm() for discard prompts and alert()/prompt() in a
    // few authoring paths. Headless Chrome has no one to answer them, and an
    // unanswered dialog freezes the renderer mid-gate.
    window.confirm = function () { return true; };
    window.alert = function () {};
    window.prompt = function () { return null; };

    // The Campaign Generator pulls the live OpenRouter model catalogue through
    // the editor server. That catalogue changes daily and needs the internet,
    // neither of which a byte-identity gate can carry. Fail that one request so
    // the modal always renders its offline branch -- what G6 photographs there
    // is the modal's chrome and its no-catalogue state, not a model list.
    var realFetch = window.fetch.bind(window);
    window.fetch = function (input) {
        var url = (typeof input === 'string') ? input : (input && input.url) || '';
        if (url.indexOf('/campaign-gen/models') >= 0) {
            return Promise.reject(new Error('G6: model catalogue suppressed'));
        }
        return realFetch.apply(null, arguments);
    };

    document.addEventListener('DOMContentLoaded', function () {
        var style = document.createElement('style');
        style.textContent =
            '*, *::before, *::after { transition: none !important;' +
            ' animation: none !important; caret-color: transparent !important; }';
        document.head.appendChild(style);
    });
})();
"""

# Resolves once webfonts and every <img> in the document are in. This is only
# half the settle: tile atlases and icon sheets are loaded as detached Image
# objects that never appear in document.images, and the canvases that draw them
# repaint whenever one lands. The other half is stable_screenshot() below.
SETTLE_JS = """
new Promise(function (resolve) {
    var imgs = Array.prototype.slice.call(document.images)
        .filter(function (i) { return !i.complete; })
        .map(function (i) {
            return new Promise(function (r) { i.onload = i.onerror = r; });
        });
    Promise.all([document.fonts.ready].concat(imgs)).then(
        function () { resolve(true); }, function () { resolve(true); });
    setTimeout(function () { resolve(true); }, 5000);
})
"""


# ---------------------------------------------------------------------------
# Chrome over the DevTools protocol. A dependency-light client rather than
# selenium/playwright: neither is installed here, and both want to download a
# driver at first run -- a gate that reaches for the network to start is a gate
# that fails for reasons that have nothing to do with the editor.
# ---------------------------------------------------------------------------

class Chrome(object):
    def __init__(self, port, profile_dir):
        exe = next((c for c in CHROME_CANDIDATES if c and os.path.exists(c)), None)
        if not exe:
            raise SystemExit("editor-screens.py: no Chrome found. Set CHROME_PATH.")
        self.proc = subprocess.Popen([
            exe,
            "--headless=new",
            "--disable-gpu",
            "--remote-debugging-port=%d" % port,
            "--user-data-dir=%s" % profile_dir,
            "--window-size=%d,%d" % VIEWPORT,
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--font-render-hinting=none",
            "--disable-lcd-text",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-background-timer-throttling",
            "--disable-renderer-backgrounding",
            "about:blank",
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        ws_url = self._wait_for_target(port)
        # suppress_origin: Chrome's DevTools endpoint 403s any handshake that
        # carries an Origin header, which websocket-client sends by default.
        self.ws = websocket.create_connection(ws_url, timeout=STEP_TIMEOUT,
                                              suppress_origin=True,
                                              max_size=64 * 1024 * 1024)
        self.msg_id = 0

    def _wait_for_target(self, port):
        deadline = time.time() + BOOT_TIMEOUT
        while time.time() < deadline:
            try:
                raw = urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % port, timeout=2).read()
                for target in json.loads(raw.decode("utf-8")):
                    if target.get("type") == "page" and target.get("webSocketDebuggerUrl"):
                        return target["webSocketDebuggerUrl"]
            except Exception:
                pass
            time.sleep(0.2)
        raise SystemExit("editor-screens.py: Chrome never exposed a debuggable page")

    def call(self, method, **params):
        self.msg_id += 1
        self.ws.send(json.dumps({"id": self.msg_id, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.msg_id:
                if "error" in msg:
                    raise RuntimeError("%s: %s" % (method, msg["error"]))
                return msg.get("result", {})

    def evaluate(self, expression, await_promise=False):
        result = self.call("Runtime.evaluate", expression=expression,
                           awaitPromise=await_promise, returnByValue=True)
        details = result.get("exceptionDetails")
        if details:
            text = details.get("exception", {}).get("description") or details.get("text")
            raise RuntimeError("page threw: %s" % text)
        return result.get("result", {}).get("value")

    def wait_for(self, expression, what):
        deadline = time.time() + STEP_TIMEOUT
        last = None
        while time.time() < deadline:
            try:
                if self.evaluate("!!(%s)" % expression):
                    return
                last = None
            except RuntimeError as exc:
                last = exc  # not built yet; the element may still be appearing
            time.sleep(0.1)
        raise SystemExit("editor-screens.py: timed out waiting for %s (%s)%s"
                         % (what, expression, ("\n  last error: %s" % last) if last else ""))

    def screenshot(self):
        return base64.b64decode(self.call("Page.captureScreenshot", format="png")["data"])

    def stable_screenshot(self, label, attempts=25, pause=0.2):
        """Shoot until two consecutive frames are byte-identical.

        The editor paints its canvases from detached Image objects (tile
        atlases, the icon sheet) that resolve on their own schedule, and every
        one that lands triggers a repaint. Waiting on a clock would either be
        too short (flaky) or too long (37 steps of dead time); waiting for the
        picture to stop changing is the thing actually being asked."""
        previous = self.screenshot()
        for _ in range(attempts):
            time.sleep(pause)
            current = self.screenshot()
            if current == previous:
                return current
            previous = current
        raise SystemExit("editor-screens.py: %s never stopped repainting -- something "
                         "on that view animates, and the gate cannot photograph it."
                         % label)

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class EditorServer(object):
    """tools/editor/server.js on a port of its own, so the gate never collides
    with (or writes through) a developer's own instance on 8080."""

    def __init__(self):
        self.port = free_port()
        env = dict(os.environ, PORT=str(self.port))
        # A log file, not a pipe: server.js logs every request, and an
        # undrained subprocess pipe blocks the writer once the OS buffer fills
        # -- which stalls the server mid-gate on whichever request happens to
        # cross the threshold.
        self.log = tempfile.NamedTemporaryFile(
            prefix="g6-editor-server-", suffix=".log", delete=False)
        self.proc = subprocess.Popen(
            ["node", SERVER_JS], cwd=ROOT, env=env,
            stdout=self.log, stderr=subprocess.STDOUT)
        self.url = "http://127.0.0.1:%d" % self.port
        self._wait_ready()

    def read_log(self):
        try:
            with open(self.log.name, "r", encoding="utf-8", errors="replace") as handle:
                return handle.read()
        except OSError:
            return ""

    def _wait_ready(self):
        deadline = time.time() + BOOT_TIMEOUT
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise SystemExit("editor-screens.py: editor server exited early:\n"
                                 + self.read_log())
            try:
                urllib.request.urlopen(self.url + "/data", timeout=2).read(1)
                return
            except Exception:
                time.sleep(0.25)
        raise SystemExit("editor-screens.py: editor server never answered on " + self.url)

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        try:
            self.log.close()
            os.unlink(self.log.name)
        except OSError:
            pass


def run_capture_set():
    """Returns [{path, image(bytes)}] for every step in STEPS."""
    steps = build_steps()
    server = EditorServer()
    profile = tempfile.mkdtemp(prefix="g6-chrome-")
    chrome = None
    try:
        chrome = Chrome(free_port(), profile)
        chrome.call("Page.enable")
        chrome.call("Runtime.enable")
        chrome.call("Emulation.setDeviceMetricsOverride",
                    width=VIEWPORT[0], height=VIEWPORT[1],
                    deviceScaleFactor=1, mobile=False)
        chrome.call("Page.addScriptToEvaluateOnNewDocument", source=DETERMINISM_JS)
        chrome.call("Page.navigate", url=server.url + "/")
        # Not the status bar: index.html ships the literal text "Database:
        # Connected" as its placeholder, so that field reads green before a
        # single byte has been fetched. Wait on the data and on the tree the
        # data builds instead.
        chrome.wait_for(
            "typeof dbPayload !== 'undefined' && dbPayload.maps && dbPayload.maps.length"
            " && document.querySelectorAll('.map-tree-item').length",
            "the editor to finish loading the database")

        captures = []
        for index, step in enumerate(steps, 1):
            print("  [%2d/%2d] %s" % (index, len(steps), step["path"]))
            chrome.evaluate(RESET_JS)
            chrome.evaluate("(function(){%s})()" % step["js"], await_promise=False)
            if step.get("wait"):
                chrome.wait_for(step["wait"], step["path"])
            chrome.evaluate(SETTLE_JS, await_promise=True)
            captures.append({"path": step["path"],
                             "image": chrome.stable_screenshot(step["path"])})
        return captures
    finally:
        if chrome:
            chrome.close()
        server.close()
        shutil.rmtree(profile, ignore_errors=True)


def safe_relpath(path):
    """STEPS is a literal in this file, so this should never trip -- but a gate
    that writes arbitrary paths is not a gate."""
    norm = os.path.normpath(path).replace("\\", "/")
    if norm.startswith("/") or norm.startswith("..") or ":" in norm:
        raise SystemExit("editor-screens.py: refusing unsafe capture path: " + path)
    return norm


def do_capture(captures):
    for cap in captures:
        dest = os.path.join(REF_DIR, safe_relpath(cap["path"]))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as handle:
            handle.write(cap["image"])
    print("Captured %d golden editor screenshots -> tools/golden/editor-screens/"
          % len(captures))


def write_actual(rel, data):
    dest = os.path.join(ACTUAL_DIR, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as handle:
        handle.write(data)


def do_check(captures):
    seen, mismatched, missing = set(), [], []

    for cap in captures:
        rel = safe_relpath(cap["path"])
        seen.add(rel)
        ref = os.path.join(REF_DIR, rel)
        if not os.path.exists(ref):
            missing.append(rel)
            write_actual(rel, cap["image"])
            continue
        with open(ref, "rb") as handle:
            if handle.read() != cap["image"]:
                mismatched.append(rel)
                write_actual(rel, cap["image"])

    # A reference with no capture is as real a change as a differing pixel: a
    # tab or modal was removed from the editor (or from STEPS).
    orphaned = []
    for dirpath, _, filenames in os.walk(REF_DIR):
        for name in filenames:
            if not name.endswith(".png"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), REF_DIR).replace("\\", "/")
            if rel not in seen:
                orphaned.append(rel)

    total = len(captures)
    print("Golden editor screenshots: %d/%d match."
          % (total - len(mismatched) - len(missing), total))
    for rel in sorted(mismatched):
        print("  MISMATCH  %s" % rel)
    for rel in sorted(missing):
        print("  NO REFERENCE  %s (new capture)" % rel)
    for rel in sorted(orphaned):
        print("  ORPHANED REFERENCE  %s (no longer captured)" % rel)

    if mismatched or missing or orphaned:
        print("")
        print("Differing frames written to tools/golden/editor-screens-actual/ --")
        print("open them side by side with tools/golden/editor-screens/ first.")
        print("")
        print("A red G6 is a VISUAL REGRESSION in the editor until proven otherwise.")
        print("Regenerating the references to make it green is an owner-signed")
        print("action, exactly as it is for G2/G3/G5 (AGENTS.md).")
        raise SystemExit(1)

    print("EDITOR SCREENS OK")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["capture", "check"])
    args = parser.parse_args()
    captures = run_capture_set()
    if args.mode == "capture":
        do_capture(captures)
    else:
        do_check(captures)


if __name__ == "__main__":
    main()
