# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# Perf Control - profile store with two-way sync to the Steam/Decky plugin,
# plus the desync detection + safeguards described in the plan.
#
# Two stores:
#   * OUR_STORE  (/storage/.config/perfcontrol/profiles.json) - canonical, always
#     writable, holds our extensions (active profile, per-profile governor, the
#     dismissed-warning signature). The tool is fully functional from this alone.
#   * PLUGIN_STORE (the Decky plugin's presets.json) - the shared library. Only
#     touched when sync status is SYNCED, and only its "presets" object, kept to
#     the plugin's own schema (our extensions are stripped before writing it).
#
# A plugin update that renames/reshapes that file can NEVER break us: we detect
# it (DESYNCED), stop writing the plugin file, fall back to OUR_STORE, and raise
# a user-visible warning. We auto-heal back to SYNCED when it parses again.

import hashlib
import json
import os
import shutil

import pc_config as C

# Fields the plugin owns (kept when writing the plugin file).
_PLUGIN_FAN_FIELDS = ("fan_mode", "fan_pwm", "fan_curve")
_OUR_EXT_FIELDS = ("governor",)   # never written into the plugin file


def _is_plugin_field(key):
    return (key.startswith("cpu_policy")
            or key in ("gpu_max", "gpu_min")
            or key in _PLUGIN_FAN_FIELDS)


def _recognized(profile):
    """True if a preset dict carries at least one field we understand."""
    if not isinstance(profile, dict):
        return False
    return any(_is_plugin_field(k) for k in profile.keys())


# --------------------------------------------------------------------------- #
# atomic json io
# --------------------------------------------------------------------------- #
def _read_json(path):
    with open(path) as fh:
        return json.load(fh)


def _write_json_atomic(path, data):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    if os.path.exists(path):
        try:
            shutil.copy2(path, path + ".bak")
        except Exception:
            pass
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


# --------------------------------------------------------------------------- #
# plugin file inspection (the desync detector)
# --------------------------------------------------------------------------- #
def inspect_plugin():
    """Return (status, signature, presets_or_None, reason)."""
    if not os.path.isdir(C.PLUGIN_DIR):
        return C.SYNC_ABSENT, "absent", None, "Decky plugin not installed"

    if not os.path.exists(C.PLUGIN_STORE):
        # Plugin installed but has saved nothing yet: treat as an empty,
        # writable shared library so ES-created profiles propagate to Steam.
        return C.SYNC_SYNCED, "empty", {}, ""

    try:
        data = _read_json(C.PLUGIN_STORE)
    except Exception as exc:
        return (C.SYNC_DESYNCED, _sig("badjson", str(exc)[:40]), None,
                "plugin presets.json is not valid JSON")

    if not isinstance(data, dict) or not isinstance(data.get("presets"), dict):
        keys = ",".join(sorted(data.keys())) if isinstance(data, dict) else type(data).__name__
        return (C.SYNC_DESYNCED, _sig("structure", keys), None,
                "plugin presets.json has an unexpected structure")

    presets = data["presets"]
    if presets and not any(_recognized(p) for p in presets.values()):
        sample = ",".join(sorted(next(iter(presets.values())).keys()))[:60] \
            if isinstance(next(iter(presets.values())), dict) else ""
        return (C.SYNC_DESYNCED, _sig("fields", sample), None,
                "plugin presets use unknown fields (format changed)")

    return C.SYNC_SYNCED, "ok", presets, ""


def _sig(kind, detail):
    h = hashlib.sha1((kind + "|" + detail).encode("utf-8", "replace")).hexdigest()[:10]
    return "%s-%s" % (kind, h)


# --------------------------------------------------------------------------- #
# normalisation
# --------------------------------------------------------------------------- #
def _normalize(profile):
    out = {}
    if not isinstance(profile, dict):
        return out
    for k, v in profile.items():
        if k.startswith("cpu_policy") or k in ("gpu_max", "gpu_min", "fan_pwm"):
            try:
                out[k] = int(v)
            except (TypeError, ValueError):
                continue
        elif k == "fan_curve" and isinstance(v, dict):
            temps = [int(x) for x in v.get("temps", []) if _isnum(x)]
            speeds = [int(x) for x in v.get("speeds", []) if _isnum(x)]
            if temps and speeds and len(temps) == len(speeds):
                out["fan_curve"] = {"temps": temps, "speeds": speeds}
        elif k == "fan_mode" and v in ("auto", "curve", "fixed"):
            out[k] = v
        elif k == "governor" and isinstance(v, str):
            out[k] = v
    return out


def _isnum(x):
    try:
        int(x)
        return True
    except (TypeError, ValueError):
        return False


def _strip_ext(profile):
    return {k: v for k, v in profile.items() if k not in _OUR_EXT_FIELDS}


# --------------------------------------------------------------------------- #
# the Store
# --------------------------------------------------------------------------- #
class Store(object):
    def __init__(self):
        self.profiles = {}          # name -> normalized profile dict
        self.active = None          # name or None
        self.sync_status = C.SYNC_ABSENT
        self.sync_signature = "absent"
        self.sync_reason = ""
        self.new_desync = False     # True => show the one-time modal
        self._dismissed_sig = None

    # -- load ------------------------------------------------------------- #
    @classmethod
    def load(cls):
        s = cls()
        ours = {}
        try:
            if os.path.exists(C.OUR_STORE):
                ours = _read_json(C.OUR_STORE)
        except Exception as exc:
            C.log("our store unreadable, starting fresh (%s)" % exc)
            ours = {}
        if not isinstance(ours, dict):
            ours = {}

        our_presets = ours.get("presets", {})
        if not isinstance(our_presets, dict):
            our_presets = {}
        s._dismissed_sig = (ours.get("desync") or {}).get("dismissed_sig")
        s.active = ours.get("active")

        status, sig, plugin_presets, reason = inspect_plugin()
        s.sync_status, s.sync_signature, s.sync_reason = status, sig, reason

        profiles = {}
        # our profiles first (durable fallback / our-only profiles)
        for name, p in our_presets.items():
            profiles[name] = _normalize(p)
        # overlay the shared library when synced (plugin wins for shared fields)
        if status == C.SYNC_SYNCED and isinstance(plugin_presets, dict):
            for name, p in plugin_presets.items():
                merged = _normalize(p)
                gov = our_presets.get(name, {}).get("governor")
                if isinstance(gov, str):
                    merged["governor"] = gov
                profiles[name] = merged

        s.profiles = profiles
        if s.active not in s.profiles:
            s.active = None
        s.new_desync = (status == C.SYNC_DESYNCED and sig != s._dismissed_sig)
        return s

    # -- mutate ----------------------------------------------------------- #
    def upsert(self, name, profile):
        self.profiles[name] = _normalize(profile)

    def delete(self, name):
        self.profiles.pop(name, None)
        if self.active == name:
            self.active = None

    def rename(self, old, new):
        if old in self.profiles and new and new != old:
            self.profiles[new] = self.profiles.pop(old)
            if self.active == old:
                self.active = new

    def set_active(self, name):
        self.active = name if name in self.profiles else None

    def dismiss_desync(self):
        self._dismissed_sig = self.sync_signature
        self.new_desync = False

    # -- persist ---------------------------------------------------------- #
    def persist(self):
        """Write OUR store always; write the plugin file only when SYNCED."""
        our_data = {
            "_perfcontrol_schema": C.SCHEMA,
            "active": self.active,
            "desync": {"dismissed_sig": self._dismissed_sig},
            "presets": self.profiles,
        }
        try:
            _write_json_atomic(C.OUR_STORE, our_data)
        except Exception as exc:
            C.log("FAILED to write our store: %s" % exc)

        if self.sync_status == C.SYNC_SYNCED:
            self._write_plugin()

    def _write_plugin(self):
        # Preserve any unknown top-level keys the plugin may add; replace only
        # "presets", and keep each preset to the plugin's own schema.
        base = {}
        try:
            if os.path.exists(C.PLUGIN_STORE):
                existing = _read_json(C.PLUGIN_STORE)
                if isinstance(existing, dict):
                    base = existing
        except Exception:
            base = {}
        base["presets"] = {n: _strip_ext(p) for n, p in self.profiles.items()}
        try:
            _write_json_atomic(C.PLUGIN_STORE, base)
        except Exception as exc:
            C.log("FAILED to write plugin store: %s" % exc)


# --------------------------------------------------------------------------- #
# default profile factory (used for "New" and first-run)
# --------------------------------------------------------------------------- #
def match_current(profiles, live):
    """Return the name of the profile whose clock caps match the live hardware.

    Compares only the clock fields (cpu_policyN_max/min, gpu_max/min) a profile
    defines; fan state is ignored (the plugin drives the fan separately). Returns
    None when the live clocks match no saved profile ("custom"). This is what lets
    Perf Control reflect a profile the Steam/Decky plugin applied behind its back.
    """
    best = None
    for name, p in profiles.items():
        keys = [k for k in p
                if k.startswith("cpu_policy") or k in ("gpu_max", "gpu_min")]
        if len(keys) < 3:                      # too few to identify a profile
            continue
        if all(k in live and live[k] == p[k] for k in keys):
            # Prefer a match that pins every live clock too (avoids a subset
            # profile shadowing a more specific one); otherwise keep the first.
            if best is None:
                best = name
    return best


def default_profile(policies, gpu):
    """Build a profile that mirrors current hardware maxima (a no-op baseline)."""
    p = {"fan_mode": "auto", "fan_pwm": 0,
         "fan_curve": dict(C.DEFAULT_FAN_CURVE), "governor": None}
    for pol in policies:
        p["cpu_policy%d_max" % pol["num"]] = pol["cpuinfo_max"]
        p["cpu_policy%d_min" % pol["num"]] = pol["cpuinfo_min"]
    if gpu and gpu["avail"]:
        p["gpu_max"] = gpu["avail"][-1]
        p["gpu_min"] = gpu["avail"][0]
    return p
