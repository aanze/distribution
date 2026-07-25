"""DUCKTALE-STREAM - launch a Steam game on the PC and stream it to the Odin.

Design notes (all three are lessons paid for by MoonDeck on 2026-07-25):

* STDLIB ONLY. Decky runs plugin backends from its own x86 PyInstaller bundle
  under FEX, while anything Steam launches runs with the NATIVE arm64 python.
  MoonDeck ships 28 native x86-64 modules (psutil, zeroconf, aiohttp deps) and
  its runner therefore dies on ImportError the moment Steam starts it. We import
  nothing outside the standard library, so both halves run anywhere.

* NO ENV FOR THE RUNNER. MoonDeck passes per-game parameters through the Steam
  shortcut's launch options ("VAR=value %command%"). On this Steam build they
  never reach the process: the runner dies on "Failed to parse runner type!"
  before doing anything. We write the parameters to LAUNCH_FILE instead and the
  runner reads them from there.

* MOONLIGHT EMBEDDED, NOT MOONLIGHT-QT. ROCKNIX ships Moonlight Embedded, whose
  CLI is "moonlight stream -app <name> -platform sdl <host>" - not the
  moonlight-qt syntax (--resolution/--audio-config) MoonDeck builds. We reuse
  the exact command ROCKNIX's own generated launchers use, and the pairing that
  is already done.

The Steam side (creating the shortcut, running it) lives in the frontend: only
it can talk to SteamClient. gamescope runs in Steam-integrated mode and focuses
ONLY what Steam declares as the running game, so launching moonlight straight
from here would stream correctly but stay behind the Steam UI (device-verified).
"""

import json
import os
import ssl
import urllib.error
import urllib.request
import base64
import decky

# Persistent, and readable by the runner (which Steam starts as a separate
# native process). Deliberately NOT in the Decky settings dir: that one is
# keyed off the plugin folder name and would move if the plugin is renamed.
CONF_DIR = "/storage/.config/ducktale-stream"
LAUNCH_FILE = os.path.join(CONF_DIR, "launch.json")
SETTINGS_FILE = os.path.join(CONF_DIR, "settings.json")

# The single Sunshine entry we drive. One generic app, re-pointed at whichever
# game the user picked, instead of one Sunshine entry per game.
DEFAULT_SUNSHINE_APP = "DUCKTALE Stream"

DEFAULTS = {
    "host": "",                  # empty => taken from the Moonlight config
    "sunshine_port": 47990,
    "sunshine_user": "",
    "sunshine_pass": "",
    "sunshine_app": DEFAULT_SUNSHINE_APP,
    "shortcut_appid": 0,         # filled in by the frontend once created
}


def _read_json(path, fallback):
    try:
        with open(path) as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else fallback
    except Exception:
        return fallback


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _settings():
    return {**DEFAULTS, **_read_json(SETTINGS_FILE, {})}


def _moonlight_host():
    """Host address from ROCKNIX's own Moonlight config, so the pairing that is
    already set up is the one we use. 'address = x.y.z.w' in moonlight.conf."""
    try:
        with open("/storage/.config/moonlight/moonlight.conf") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("address") and "=" in line:
                    return line.split("=", 1)[1].strip()
    except Exception:
        pass
    return ""


def _host(settings=None):
    settings = settings or _settings()
    return (settings.get("host") or "").strip() or _moonlight_host()


def _sunshine_request(settings, path, method="GET", payload=None, timeout=10):
    """Sunshine's REST API, HTTPS with a self-signed certificate and basic auth."""
    host = _host(settings)
    if not host:
        raise RuntimeError("no host configured (and none found in moonlight.conf)")
    user = settings.get("sunshine_user") or ""
    password = settings.get("sunshine_pass") or ""
    if not user or not password:
        raise RuntimeError("Sunshine credentials not set")

    url = f"https://{host}:{int(settings.get('sunshine_port') or 47990)}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    if data:
        req.add_header("Content-Type", "application/json")

    # Sunshine ships a self-signed cert by design; there is nothing to verify
    # against on a LAN box, so verification is disabled for this call only.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        body = resp.read().decode("utf-8", "replace")
    return json.loads(body) if body.strip() else {}


class Plugin:

    # ---------------------------------------------------------------- settings
    async def get_settings(self):
        settings = _settings()
        settings["resolved_host"] = _host(settings)
        settings["moonlight_installed"] = os.path.exists("/usr/bin/moonlight")
        # Never hand the password back to the UI; only whether one is stored.
        settings["sunshine_pass"] = ""
        settings["has_password"] = bool(_settings().get("sunshine_pass"))
        return settings

    async def set_settings(self, patch: dict):
        settings = _settings()
        for key, value in (patch or {}).items():
            if key in DEFAULTS:
                # An empty password means "leave the stored one alone", so the
                # UI can save other fields without re-typing it every time.
                if key == "sunshine_pass" and not value:
                    continue
                settings[key] = value
        _write_json(SETTINGS_FILE, settings)
        return await self.get_settings()

    # ------------------------------------------------------------------ status
    async def get_host_status(self):
        """Is the streaming host up? Uses the unauthenticated GameStream port,
        which answers whether or not this client is paired."""
        host = _host()
        if not host:
            return {"ok": False, "reason": "no host"}
        try:
            with urllib.request.urlopen(
                    f"http://{host}:47989/serverinfo", timeout=4) as resp:
                body = resp.read().decode("utf-8", "replace")
        except Exception as exc:
            return {"ok": False, "host": host, "reason": str(exc)}

        def tag(name):
            start = body.find(f"<{name}>")
            end = body.find(f"</{name}>")
            return body[start + len(name) + 2:end] if start >= 0 and end > start else ""

        return {"ok": True, "host": host, "hostname": tag("hostname"),
                "state": tag("state"), "busy": tag("state").endswith("_BUSY")}

    # ------------------------------------------------------------- the launch
    async def prepare_stream(self, appid: int, game_name: str):
        """Point the Sunshine entry at this game and stage the runner's input.

        Returns {"ok": bool, ...}. The frontend calls this FIRST and only runs
        the Steam shortcut if it succeeded - otherwise Steam would focus a
        runner that has nothing to stream.
        """
        settings = _settings()
        host = _host(settings)
        app_name = settings.get("sunshine_app") or DEFAULT_SUNSHINE_APP

        try:
            apps = (_sunshine_request(settings, "/api/apps") or {}).get("apps", [])
        except Exception as exc:
            decky.logger.error(f"Sunshine app list failed: {exc}")
            return {"ok": False, "step": "sunshine-list", "error": str(exc)}

        index = -1
        for position, app in enumerate(apps):
            if app.get("name") == app_name:
                # Sunshine identifies an app to edit by its index; a fresh entry
                # uses -1. Prefer the index the server itself reports if present.
                index = app.get("index", position)
                break

        entry = {
            "name": app_name,
            "index": index,
            "output": "",
            "cmd": "",
            # detached: Sunshine fires the URI and does not wait for it, which
            # is what we want - Steam on the host owns the game's lifetime.
            "detached": [f"steam://rungameid/{int(appid)}"],
            "exclude-global-prep-cmd": False,
            "elevated": False,
            "auto-detach": True,
            "wait-all": True,
            "exit-timeout": 5,
            "prep-cmd": [],
            "image-path": "",
        }
        try:
            _sunshine_request(settings, "/api/apps", method="POST", payload=entry)
        except Exception as exc:
            decky.logger.error(f"Sunshine app upsert failed: {exc}")
            return {"ok": False, "step": "sunshine-upsert", "error": str(exc)}

        _write_json(LAUNCH_FILE, {
            "host": host,
            "app": app_name,
            "steam_appid": int(appid),
            "game_name": game_name or "",
        })
        decky.logger.info(f"staged stream: {game_name} ({appid}) via '{app_name}' on {host}")
        return {"ok": True, "host": host, "app": app_name}

    async def get_last_launch(self):
        return _read_json(LAUNCH_FILE, {})

    async def _main(self):
        os.makedirs(CONF_DIR, exist_ok=True)
        decky.logger.info(f"DUCKTALE-STREAM loaded. Host: {_host() or '(none)'}")

    async def _unload(self):
        decky.logger.info("DUCKTALE-STREAM unloaded.")
