#!/usr/bin/env python3
"""Run the local Stable Diffusion server that the `forge-*` providers talk to.

WHY THIS EXISTS RATHER THAN "just start the web UI": the API is off by default,
and Forge's own `webui-user.bat` SETS `COMMANDLINE_ARGS`, so exporting it in the
environment does nothing -- the batch file overwrites it a moment later. Rather
than edit an install that lives outside this repo, this reproduces what
`environment.bat` does (put the embedded python and git on PATH, skip the venv)
and calls `webui.bat` directly with the arguments we need.

    python tools/asset-gen/forge.py start     # launch, detached, logging to out/
    python tools/asset-gen/forge.py status    # is it up, and with which model
    python tools/asset-gen/forge.py stop

The install is found at FORGE_HOME, falling back to the known path. Nothing here
writes into it.

The launch flags are the ones a 4 GB card needs: --medvram --lowram keep the
model off the GPU except while it is being used, and --xformers cuts attention
memory. They match what the install already uses; only --api is added.
"""

import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import classes  # noqa: E402

import requests  # noqa: E402

DEFAULT_HOME = r"D:\AI\webui_forge_cu121_torch231"
BASE_URL = os.environ.get("FORGE_URL", "http://127.0.0.1:7860")
ARGS = "--xformers --no-half-vae --medvram --lowram --api"


def home():
    path = os.environ.get("FORGE_HOME") or DEFAULT_HOME
    if not os.path.isdir(path):
        raise SystemExit(
            f"no Forge install at {path}. Set FORGE_HOME to the folder holding "
            "environment.bat and webui/")
    return path


def _out_dir():
    path = os.path.join(classes.ROOT, "tools", "asset-gen", "out")
    os.makedirs(path, exist_ok=True)
    return path


def _pid_file():
    return os.path.join(_out_dir(), "forge.pid")


def _log_file():
    return os.path.join(_out_dir(), "forge.log")


# ---------------------------------------------------------------------------
def ping(timeout=3):
    """Returns the model list, or None if the server is not answering yet."""
    try:
        res = requests.get(f"{BASE_URL}/sdapi/v1/sd-models", timeout=timeout)
        if res.ok:
            return res.json()
    except requests.RequestException:
        pass
    return None


def current_model():
    try:
        res = requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=5)
        if res.ok:
            return res.json().get("sd_model_checkpoint")
    except requests.RequestException:
        pass
    return None


def wait_until_up(deadline_seconds=600, quiet=False):
    """Block until the API answers. First start loads a model and is slow."""
    started = time.time()
    while time.time() - started < deadline_seconds:
        models = ping()
        if models is not None:
            return models
        if not quiet:
            print(f"  waiting for {BASE_URL} ... {time.time() - started:.0f}s", flush=True)
        time.sleep(5)
    return None


# ---------------------------------------------------------------------------
def cmd_start(args):
    if ping() is not None:
        print(f"already up at {BASE_URL}")
        return 0

    root = home()
    system = os.path.join(root, "system")
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([
        os.path.join(system, "git", "bin"),
        os.path.join(system, "python"),
        os.path.join(system, "python", "Scripts"),
        env.get("PATH", ""),
    ])
    env["SKIP_VENV"] = "1"
    env["PY_LIBS"] = os.pathsep.join([
        os.path.join(system, "python", "Scripts", "Lib"),
        os.path.join(system, "python", "Scripts", "Lib", "site-packages"),
    ])
    env["PY_PIP"] = os.path.join(system, "python", "Scripts")
    env["PIP_INSTALLER_LOCATION"] = os.path.join(system, "python", "get-pip.py")
    env["TRANSFORMERS_CACHE"] = os.path.join(system, "transformers-cache")
    # The whole reason for this launcher. Safe to set here because webui.bat
    # reads COMMANDLINE_ARGS but never sets it -- it is run.bat -> webui-user.bat
    # that hard-codes the value, and we bypass both.
    env["COMMANDLINE_ARGS"] = ARGS

    log = open(_log_file(), "ab")
    log.write(f"\n=== start {time.strftime('%Y-%m-%d %H:%M:%S')} {ARGS} ===\n"
              .encode("utf-8"))
    log.flush()
    flags = 0
    if os.name == "nt":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    process = subprocess.Popen(
        # Absolute path, not "webui.bat": a detached cmd does not reliably
        # resolve a bare batch name against the working directory.
        ["cmd", "/c", os.path.join(root, "webui", "webui.bat")],
        cwd=os.path.join(root, "webui"),
        env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        creationflags=flags,
    )
    with open(_pid_file(), "w", encoding="utf-8") as handle:
        handle.write(str(process.pid))
    print(f"launched (pid {process.pid}), logging to {_log_file()}")

    if args.no_wait:
        print("not waiting; run `forge.py status` to check")
        return 0
    models = wait_until_up(args.timeout)
    if models is None:
        print(f"error: still not answering after {args.timeout}s. "
              f"Read {_log_file()}", file=sys.stderr)
        return 1
    print(f"up at {BASE_URL} with {len(models)} checkpoint(s)")
    return 0


def cmd_status(args):
    models = ping()
    if models is None:
        print(f"down (nothing answering at {BASE_URL})")
        return 1
    print(f"up at {BASE_URL}")
    print(f"  loaded: {current_model()}")
    print(f"  {len(models)} checkpoint(s) available")
    if args.verbose:
        for model in models:
            print(f"    {model['model_name']}")
    return 0


def cmd_stop(args):
    if not os.path.isfile(_pid_file()):
        print("no pid file; nothing this tool started")
        return 1
    with open(_pid_file(), "r", encoding="utf-8") as handle:
        pid = handle.read().strip()
    # The tree, not the pid: webui.bat spawns python as a child, and killing the
    # batch file alone leaves the server holding the port.
    subprocess.run(["taskkill", "/PID", pid, "/T", "/F"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.remove(_pid_file())
    print(f"stopped (pid {pid})")
    return 0


def cmd_models(args):
    """What is installed, so a prompt can name a checkpoint or LoRA that exists."""
    models = ping()
    if models is None:
        raise SystemExit("server is down; run `forge.py start`")
    print("CHECKPOINTS")
    for model in sorted(models, key=lambda m: m["model_name"]):
        print(f"  {model['model_name']}")
    try:
        loras = requests.get(f"{BASE_URL}/sdapi/v1/loras", timeout=10).json()
        print("\nLORAS")
        for lora in sorted(loras, key=lambda l: l["name"]):
            print(f"  {lora['name']}")
    except (requests.RequestException, json.JSONDecodeError):
        pass
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="forge", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    start = sub.add_parser("start", help="launch the server, detached")
    start.add_argument("--no-wait", action="store_true", help="return immediately")
    start.add_argument("--timeout", type=int, default=600,
                       help="seconds to wait for the API (default 600)")

    status = sub.add_parser("status", help="is it up, and with which model")
    status.add_argument("--verbose", action="store_true", help="list every checkpoint")

    sub.add_parser("stop", help="kill the server this tool started")
    sub.add_parser("models", help="list installed checkpoints and LoRAs")

    args = parser.parse_args(argv)
    return {"start": cmd_start, "status": cmd_status,
            "stop": cmd_stop, "models": cmd_models}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
