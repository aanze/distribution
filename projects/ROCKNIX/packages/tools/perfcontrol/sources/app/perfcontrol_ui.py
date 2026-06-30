#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# Perf Control - Pyxel GUI (gamepad driven, full screen via sway).
# Runs under the gamepadcalibration venv so `import pyxel` resolves.
# All hardware/profile logic lives in the pure-stdlib pc_* modules.

import os
import sys
import time
import json
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pyxel  # noqa: E402  (provided by the gamepadcalibration venv)

import pc_config as C   # noqa: E402
import pc_hardware as hw  # noqa: E402
import pc_profiles as P  # noqa: E402
import pc_apply as A     # noqa: E402

W, H = 360, 240

# palette indices (pyxel default 16-col palette)
BG, FG, DIM, HEAD, OK, BAD, WARN, SEL = 1, 7, 13, 10, 11, 8, 9, 6

TABS = ["PROFILES", "CPU", "GPU", "FAN", "DRIVER", "MONITOR"]

GPU_DRIVER_BIN = "/usr/bin/gpu-driver"

# Per-scope driver assignment in the DRIVER tab. "Default" = the global default
# applied to every game. The rest are per-SYSTEM overrides keyed by the
# EmulationStation platform name (what runemu passes), via gpu-driver's
# "@<platform>" key. These are the Vulkan-heavy emulators where the Turnip
# version actually matters (RPCS3/Citron the headline cases).
DRIVER_SCOPES = [
    ("Default (all games)", None),
    ("RPCS3  (ps3)", "@ps3"),
    ("Citron (switch)", "@switch"),
    ("PCSX2  (ps2)", "@ps2"),
    ("Cemu   (wiiu)", "@wiiu"),
    ("Dolphin (gamecube)", "@gamecube"),
    ("Dolphin (wii)", "@wii"),
]


# --------------------------------------------------------------------------- #
# input: map keyboard + gamepad onto logical actions
#
# Constants are resolved by NAME so a minor Pyxel version difference (a renamed
# button) can never crash the whole UI at import time - unknown names are just
# skipped.
# --------------------------------------------------------------------------- #
def _K(*names):
    out = []
    for n in names:
        v = getattr(pyxel, n, None)
        if v is not None:
            out.append(v)
    return out


KEYS_UP = _K("KEY_UP", "GAMEPAD1_BUTTON_DPAD_UP")
KEYS_DOWN = _K("KEY_DOWN", "GAMEPAD1_BUTTON_DPAD_DOWN")
KEYS_LEFT = _K("KEY_LEFT", "GAMEPAD1_BUTTON_DPAD_LEFT")
KEYS_RIGHT = _K("KEY_RIGHT", "GAMEPAD1_BUTTON_DPAD_RIGHT")
KEYS_A = _K("KEY_RETURN", "KEY_Z", "GAMEPAD1_BUTTON_A")
KEYS_B = _K("KEY_BACKSPACE", "KEY_X", "GAMEPAD1_BUTTON_B")
KEYS_X = _K("KEY_C", "GAMEPAD1_BUTTON_X")
KEYS_Y = _K("KEY_V", "GAMEPAD1_BUTTON_Y")
KEYS_L = _K("KEY_Q", "GAMEPAD1_BUTTON_LEFTSHOULDER")
KEYS_R = _K("KEY_E", "GAMEPAD1_BUTTON_RIGHTSHOULDER")
KEYS_START = _K("KEY_S", "GAMEPAD1_BUTTON_START")
KEYS_DELETE = _K("KEY_DELETE", "GAMEPAD1_BUTTON_BACK")


def _p(keys, hold=0, rep=0):
    for k in keys:
        if hold:
            if pyxel.btnp(k, hold, rep):
                return True
        elif pyxel.btnp(k):
            return True
    return False


def UP(r=False):
    return _p(KEYS_UP, *((15, 3) if r else (0, 0)))


def DOWN(r=False):
    return _p(KEYS_DOWN, *((15, 3) if r else (0, 0)))


def LEFT():
    return _p(KEYS_LEFT, 20, 3)


def RIGHT():
    return _p(KEYS_RIGHT, 20, 3)


def A_BTN():
    return _p(KEYS_A)


def B_BTN():
    return _p(KEYS_B)


def X_BTN():
    return _p(KEYS_X)


def Y_BTN():
    return _p(KEYS_Y)


def L_BTN():
    return _p(KEYS_L)


def R_BTN():
    return _p(KEYS_R)


def START():
    return _p(KEYS_START)


def DELETE_BTN():
    return _p(KEYS_DELETE)


# --------------------------------------------------------------------------- #
# gamepad text entry overlay
# --------------------------------------------------------------------------- #
class Keyboard(object):
    ROWS = ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789 -_."]

    def __init__(self, title, text, on_done):
        self.title = title
        self.text = text
        self.on_done = on_done
        self.cx = 0
        self.cy = 0

    def update(self):
        if UP():
            self.cy = (self.cy - 1) % len(self.ROWS)
        if DOWN():
            self.cy = (self.cy + 1) % len(self.ROWS)
        if LEFT():
            self.cx = (self.cx - 1) % len(self.ROWS[self.cy])
        if RIGHT():
            self.cx = (self.cx + 1) % len(self.ROWS[self.cy])
        if A_BTN():
            self.text += self.ROWS[self.cy][self.cx]
        if X_BTN():
            self.text = self.text[:-1]
        if Y_BTN() or START():
            self.on_done(self.text.strip())
            return True
        if B_BTN():
            self.on_done(None)
            return True
        return False

    def draw(self):
        pyxel.rect(20, 40, W - 40, H - 80, 0)
        pyxel.rectb(20, 40, W - 40, H - 80, FG)
        pyxel.text(30, 50, self.title, HEAD)
        pyxel.rect(30, 62, W - 60, 10, BG)
        pyxel.text(34, 65, self.text + "_", FG)
        y0 = 85
        for ry, row in enumerate(self.ROWS):
            for rx, ch in enumerate(row):
                x = 34 + rx * 26
                y = y0 + ry * 16
                if rx == self.cx and ry == self.cy:
                    pyxel.rect(x - 3, y - 2, 11, 11, SEL)
                pyxel.text(x, y, ch if ch != " " else "sp", FG)
        pyxel.text(30, H - 48, "A:type  X:del  Y/Start:ok  B:cancel", DIM)


# --------------------------------------------------------------------------- #
# main app
# --------------------------------------------------------------------------- #
class App(object):
    def __init__(self):
        self.store = P.Store.load()
        self.policies = hw.list_cpu_policies()
        self.gpu = hw.find_gpu()
        self.govs = ["keep"] + hw.available_governors()
        self.tab = 0
        self.toast = ""
        self.toast_t = 0
        self.modal = None          # ("desync"|("confirm", text, cb)) or Keyboard
        self.kbd = None

        # selection cursors
        self.prof_idx = 0
        self.cpu_idx = 0
        self.cpu_field = "max"     # max|min
        self.gpu_idx = 0           # 0 max, 1 min, 2 governor
        self.fan_idx = 0
        self.fan_field = "temp"    # temp|pwm
        self._mon_last = 0
        self._mon = {}

        # GPU Driver tab state (swappable Mesa Turnip / Vulkan driver)
        self.drv_idx = 0
        self.drv_scope_idx = 0     # 0=Default, else a per-system override scope
        self.drv_rows = []
        self.drv_default = "stock"
        self.drv_per_game = {}     # {"@ps3": "<id>", ...}
        self.drv_avail = os.path.exists(GPU_DRIVER_BIN)
        self._drv_loaded = False

        # Reflect reality: detect which profile the hardware is actually running
        # (the Steam/Decky plugin may have applied one behind our back) and make
        # it the active selection so the marker is never stale. None = "custom".
        #
        # CRUCIAL: only ADOPT a live match when it is a real, *different* saved
        # profile. NEVER overwrite the persisted selection with None just because
        # the live clocks match nothing: that happens routinely when the live
        # caps have merely drifted (after an OTA the OPP table can shift so the
        # stored exact freqs snap elsewhere; the backgrounded boot re-apply can
        # lose a race; a Steam session or suspend/resume can reset caps) and
        # writing None here would silently, permanently reset a profile that is
        # still perfectly valid in our store. Keep `active`; the boot quirk then
        # re-asserts it, and `self.live_name` (possibly None) still drives the
        # "custom" indicator without destroying the user's choice.
        self.live_name = P.match_current(self.store.profiles, hw.live_clocks())
        if self.live_name is not None:
            # Hardware matches a saved profile (maybe one the Steam/Decky plugin
            # applied behind our back) -> adopt it as the selection.
            if self.live_name != self.store.active:
                self.store.active = self.live_name
                self.store.persist()
        elif self.store.active in self.store.profiles:
            # Nothing matches but we DO have a persisted selection: the live caps
            # have merely drifted. Re-ASSERT the profile (clocks only, like the
            # boot quirk) instead of discarding it, so opening Perf Control
            # restores the underclock rather than the old code's silent reset.
            A.apply_caps(self.store.profiles[self.store.active])
            self.live_name = self.store.active
        _names = self.names()
        if self.store.active in _names:
            self.prof_idx = _names.index(self.store.active)

        # working copy of the selected profile
        self.cur_name = None
        self.work = None
        self._load_selected()

        if self.store.new_desync:
            self.modal = "desync"

        pyxel.init(W, H, title="Perf Control", fps=30, quit_key=pyxel.KEY_NONE)
        pyxel.run(self.update, self.draw)

    # -- helpers ---------------------------------------------------------- #
    def names(self):
        return sorted(self.store.profiles)

    def _load_selected(self):
        names = self.names()
        if not names:
            self.cur_name = None
            self.work = P.default_profile(self.policies, self.gpu)
            return
        self.prof_idx = max(0, min(self.prof_idx, len(names) - 1))
        self.cur_name = names[self.prof_idx]
        # deep-ish copy so edits don't mutate the store until saved
        src = self.store.profiles[self.cur_name]
        self.work = dict(src)
        if "fan_curve" in src:
            self.work["fan_curve"] = {"temps": list(src["fan_curve"]["temps"]),
                                      "speeds": list(src["fan_curve"]["speeds"])}

    def say(self, msg):
        self.toast = msg
        self.toast_t = time.time()

    def _save(self, applyhw=False):
        if self.cur_name is None:
            self.say("Use X to create a profile first")
            return
        self.store.upsert(self.cur_name, self.work)
        if applyhw:
            A.apply_profile(self.store.profiles[self.cur_name], fan=True)
            self.store.set_active(self.cur_name)
        self.store.persist()
        self.say(("Applied + saved '%s'" if applyhw else "Saved '%s'") % self.cur_name)

    # -- update ----------------------------------------------------------- #
    def update(self):
        if self.kbd is not None:
            if self.kbd.update():
                self.kbd = None
            return
        if self.modal == "desync":
            if A_BTN() or B_BTN():
                self.store.dismiss_desync()
                self.store.persist()
                self.modal = None
            return
        if isinstance(self.modal, tuple) and self.modal[0] == "confirm":
            if A_BTN():
                self.modal[2]()
                self.modal = None
            elif B_BTN():
                self.modal = None
            return

        if L_BTN():
            self.tab = (self.tab - 1) % len(TABS)
            self._drv_loaded = False
        if R_BTN():
            self.tab = (self.tab + 1) % len(TABS)
            self._drv_loaded = False

        name = TABS[self.tab]
        if name in ("CPU", "GPU", "FAN", "DRIVER") and B_BTN():
            self.tab = 0          # B = back to the profile list
            return
        if name == "PROFILES":
            self.upd_profiles()
        elif name == "CPU":
            self.upd_cpu()
        elif name == "GPU":
            self.upd_gpu()
        elif name == "FAN":
            self.upd_fan()
        elif name == "DRIVER":
            self.upd_driver()
        elif name == "MONITOR":
            if B_BTN():
                pyxel.quit()

    # -- gpu driver ------------------------------------------------------- #
    def _gpud(self, args, timeout=20):
        try:
            return subprocess.run([GPU_DRIVER_BIN] + args,
                                  capture_output=True, text=True, timeout=timeout)
        except Exception:
            return None

    def _load_drivers(self):
        self.drv_rows = []
        self.drv_default = "stock"
        self.drv_avail = os.path.exists(GPU_DRIVER_BIN)
        if not self.drv_avail:
            return
        installed = set()
        out = self._gpud(["list", "--json"])
        if out and out.returncode == 0:
            try:
                d = json.loads(out.stdout)
                self.drv_default = d.get("default", "stock")
                self.drv_per_game = d.get("per_game", {}) or {}
                for x in d.get("drivers", []):
                    self.drv_rows.append({"id": x["id"], "ver": x.get("mesa_version", "?"),
                                          "ch": x.get("channel", "?"),
                                          "fav": bool(x.get("favorite")), "installed": True})
                    installed.add(x["id"])
            except Exception:
                pass
        cat = self._gpud(["catalog", "--json"])
        if cat and cat.returncode == 0:
            try:
                for x in json.loads(cat.stdout).get("drivers", []):
                    if x.get("id") not in installed:
                        self.drv_rows.append({"id": x["id"], "ver": x.get("mesa_version", "?"),
                                              "ch": x.get("channel", "?"),
                                              "fav": False, "installed": False})
            except Exception:
                pass
        if self.drv_idx >= len(self.drv_rows):
            self.drv_idx = max(0, len(self.drv_rows) - 1)

    def _scope_current(self):
        """Driver id currently assigned to the selected scope (None = use default)."""
        key = DRIVER_SCOPES[self.drv_scope_idx][1]
        if key is None:
            return self.drv_default
        return self.drv_per_game.get(key)

    def upd_driver(self):
        if not self._drv_loaded:
            self._load_drivers()
            self._drv_loaded = True
        rows = self.drv_rows
        # Left/Right pick the SCOPE (Default / RPCS3 / Citron / ...)
        if LEFT():
            self.drv_scope_idx = (self.drv_scope_idx - 1) % len(DRIVER_SCOPES)
        if RIGHT():
            self.drv_scope_idx = (self.drv_scope_idx + 1) % len(DRIVER_SCOPES)
        # Up/Down pick the DRIVER
        if UP(True) and rows:
            self.drv_idx = (self.drv_idx - 1) % len(rows)
        if DOWN(True) and rows:
            self.drv_idx = (self.drv_idx + 1) % len(rows)
        if X_BTN():
            self.say("Refreshing catalog...")
            self._gpud(["catalog", "--refresh"], timeout=40)
            self._load_drivers()
            self.say("Catalog refreshed")
            return
        scope_key = DRIVER_SCOPES[self.drv_scope_idx][1]
        scope_name = DRIVER_SCOPES[self.drv_scope_idx][0]
        # Delete/Back-select clears a per-system override (-> falls back to default)
        if DELETE_BTN() and scope_key is not None:
            self._gpud(["set-game", scope_key, "clear"])
            self.say("%s -> use default" % scope_name)
            self._load_drivers()
            return
        if not rows:
            return
        row = rows[self.drv_idx]
        if A_BTN():
            # Install first if this is a catalogue (not-yet-installed) entry.
            if not row["installed"]:
                self.say("Installing %s (downloading)..." % row["id"])
                r = self._gpud(["install", row["id"]], timeout=180)
                if not (r and r.returncode == 0):
                    self.say("Install failed (check network)")
                    self._load_drivers()
                    return
                self._load_drivers()
            # Assign the (now installed) driver to the selected scope.
            if scope_key is None:
                self._gpud(["set-default", row["id"]])
            else:
                self._gpud(["set-game", scope_key, row["id"]])
            self.say("%s -> %s" % (scope_name, row["id"]))
            self._load_drivers()
        elif Y_BTN() and row["installed"] and row["id"] != "stock":
            self._gpud(["favorite", row["id"]] + ([] if not row["fav"] else ["--off"]))
            self._load_drivers()

    # -- profiles --------------------------------------------------------- #
    def upd_profiles(self):
        names = self.names()
        if UP(True) and names:
            self.prof_idx = (self.prof_idx - 1) % len(names)
            self._load_selected()
        if DOWN(True) and names:
            self.prof_idx = (self.prof_idx + 1) % len(names)
            self._load_selected()
        if A_BTN():
            self._save(applyhw=True)
        if START():
            self._save(applyhw=False)
        if X_BTN():
            self._new_profile()
        if Y_BTN() and self.cur_name:
            self.kbd = Keyboard("Rename profile", self.cur_name, self._do_rename)
        if B_BTN():
            pyxel.quit()
        # delete = SELECT/BACK button
        if DELETE_BTN() and self.cur_name:
            target = self.cur_name
            self.modal = ("confirm", "Delete '%s'?" % target,
                          lambda: self._do_delete(target))

    def _new_profile(self):
        def done(nm):
            if nm:
                base = P.default_profile(self.policies, self.gpu)
                # seed from current hardware so it's a sane starting point
                self.store.upsert(nm, base)
                self.store.persist()
                names = self.names()
                self.prof_idx = names.index(nm) if nm in names else 0
                self._load_selected()
                self.say("Created '%s'" % nm)
        self.kbd = Keyboard("New profile name", "", done)

    def _do_rename(self, nm):
        if nm and nm != self.cur_name:
            self.store.rename(self.cur_name, nm)
            self.store.persist()
            names = self.names()
            self.prof_idx = names.index(nm) if nm in names else 0
            self._load_selected()
            self.say("Renamed to '%s'" % nm)

    def _do_delete(self, name):
        self.store.delete(name)
        self.store.persist()
        self.prof_idx = 0
        self._load_selected()
        self.say("Deleted '%s'" % name)

    # -- cpu -------------------------------------------------------------- #
    def upd_cpu(self):
        rows = len(self.policies) + 1   # + governor row
        if UP(True):
            self.cpu_idx = (self.cpu_idx - 1) % rows
        if DOWN(True):
            self.cpu_idx = (self.cpu_idx + 1) % rows
        if self.cpu_idx < len(self.policies):
            if X_BTN():
                self.cpu_field = "min" if self.cpu_field == "max" else "max"
            pol = self.policies[self.cpu_idx]
            key = "cpu_policy%d_%s" % (pol["num"], self.cpu_field)
            cur = self.work.get(key, pol["cpuinfo_max"] if self.cpu_field == "max"
                                else pol["cpuinfo_min"])
            if LEFT():
                self.work[key] = self._step_freq(pol["avail"], cur, -1)
                self._cpu_fix_order(pol)
            if RIGHT():
                self.work[key] = self._step_freq(pol["avail"], cur, +1)
                self._cpu_fix_order(pol)
        else:
            # governor row
            cur = self.work.get("governor") or "keep"
            if cur not in self.govs:
                self.govs.append(cur)
            i = self.govs.index(cur)
            if LEFT():
                i = (i - 1) % len(self.govs)
            if RIGHT():
                i = (i + 1) % len(self.govs)
            sel = self.govs[i]
            self.work["governor"] = None if sel == "keep" else sel

    def _cpu_fix_order(self, pol):
        kmin = "cpu_policy%d_min" % pol["num"]
        kmax = "cpu_policy%d_max" % pol["num"]
        if kmin in self.work and kmax in self.work and self.work[kmin] > self.work[kmax]:
            if self.cpu_field == "max":
                self.work[kmin] = self.work[kmax]
            else:
                self.work[kmax] = self.work[kmin]

    @staticmethod
    def _step_freq(avail, cur, direction):
        if not avail:
            return cur
        if cur in avail:
            i = avail.index(cur)
        else:
            i = min(range(len(avail)), key=lambda j: abs(avail[j] - cur))
        return avail[max(0, min(len(avail) - 1, i + direction))]

    # -- gpu -------------------------------------------------------------- #
    def upd_gpu(self):
        if not self.gpu:
            return
        if UP(True):
            self.gpu_idx = (self.gpu_idx - 1) % 2
        if DOWN(True):
            self.gpu_idx = (self.gpu_idx + 1) % 2
        key = "gpu_max" if self.gpu_idx == 0 else "gpu_min"
        cur = self.work.get(key, self.gpu["avail"][-1] if self.gpu_idx == 0
                            else self.gpu["avail"][0])
        if LEFT():
            self.work[key] = self._step_freq(self.gpu["avail"], cur, -1)
        if RIGHT():
            self.work[key] = self._step_freq(self.gpu["avail"], cur, +1)
        if self.work.get("gpu_min", 0) > self.work.get("gpu_max", 1 << 62):
            if key == "gpu_max":
                self.work["gpu_min"] = self.work["gpu_max"]
            else:
                self.work["gpu_max"] = self.work["gpu_min"]

    # -- fan -------------------------------------------------------------- #
    def _curve(self):
        c = self.work.get("fan_curve")
        if not c:
            c = {"temps": list(C.DEFAULT_FAN_CURVE["temps"]),
                 "speeds": list(C.DEFAULT_FAN_CURVE["speeds"])}
            self.work["fan_curve"] = c
        return c

    def upd_fan(self):
        mode = self.work.get("fan_mode", "auto")
        c = self._curve()
        npts = len(c["temps"])
        rows = 1 + (npts if mode == "curve" else (1 if mode == "fixed" else 0))
        if UP(True):
            self.fan_idx = (self.fan_idx - 1) % max(1, rows)
        if DOWN(True):
            self.fan_idx = (self.fan_idx + 1) % max(1, rows)

        if self.fan_idx == 0:   # mode row
            modes = ["auto", "curve", "fixed"]
            i = modes.index(mode) if mode in modes else 0
            if LEFT():
                self.work["fan_mode"] = modes[(i - 1) % 3]
            if RIGHT():
                self.work["fan_mode"] = modes[(i + 1) % 3]
            return

        if mode == "fixed":
            cur = A._clamp_pwm(self.work.get("fan_pwm", 0))
            if LEFT():
                self.work["fan_pwm"] = max(0, cur - 8)
            if RIGHT():
                self.work["fan_pwm"] = min(C.PWM_MAX, cur + 8)
            return

        # curve mode: editing a point
        pi = self.fan_idx - 1
        if X_BTN():
            self.fan_field = "pwm" if self.fan_field == "temp" else "temp"
        if Y_BTN() and npts > 1:           # delete point
            del c["temps"][pi]
            del c["speeds"][pi]
            self.fan_idx = min(self.fan_idx, npts - 1)
            return
        if A_BTN():                        # insert a point after this one
            t = c["temps"][pi]
            nt = min(120000, t + 5000)
            c["temps"].insert(pi + 1, nt)
            c["speeds"].insert(pi + 1, c["speeds"][pi])
            self._sort_curve(c)
            return
        if self.fan_field == "temp":
            if LEFT():
                c["temps"][pi] = max(0, c["temps"][pi] - 1000)
            if RIGHT():
                c["temps"][pi] = min(120000, c["temps"][pi] + 1000)
        else:
            if LEFT():
                c["speeds"][pi] = max(0, c["speeds"][pi] - 8)
            if RIGHT():
                c["speeds"][pi] = min(C.PWM_MAX, c["speeds"][pi] + 8)

    @staticmethod
    def _sort_curve(c):
        order = sorted(range(len(c["temps"])), key=lambda j: c["temps"][j])
        c["temps"] = [c["temps"][j] for j in order]
        c["speeds"] = [c["speeds"][j] for j in order]

    # ------------------------------------------------------------------ draw
    def draw(self):
        pyxel.cls(BG)
        self._draw_tabs()
        name = TABS[self.tab]
        if name == "PROFILES":
            self.draw_profiles()
        elif name == "CPU":
            self.draw_cpu()
        elif name == "GPU":
            self.draw_gpu()
        elif name == "FAN":
            self.draw_fan()
        elif name == "DRIVER":
            self.draw_driver()
        elif name == "MONITOR":
            self.draw_monitor()
        self._draw_toast()
        if self.kbd is not None:
            self.kbd.draw()
        elif self.modal == "desync":
            self._draw_desync()
        elif isinstance(self.modal, tuple) and self.modal[0] == "confirm":
            self._draw_confirm(self.modal[1])

    def _draw_tabs(self):
        pyxel.rect(0, 0, W, 12, 0)
        x = 4
        for i, t in enumerate(TABS):
            col = HEAD if i == self.tab else DIM
            if i == self.tab:
                pyxel.rect(x - 2, 0, len(t) * 4 + 4, 11, BG)
            pyxel.text(x, 3, t, col)
            x += len(t) * 4 + 8
        # sync badge top-right
        st = self.store.sync_status
        if st == C.SYNC_SYNCED:
            pyxel.text(W - 60, 3, "Steam:sync", OK)
        elif st == C.SYNC_ABSENT:
            pyxel.text(W - 64, 3, "Steam:none", DIM)
        else:
            pyxel.text(W - 70, 3, "Steam:DESYNC", BAD)

    def draw_profiles(self):
        pyxel.text(6, 16, "PROFILES", HEAD)
        # What the hardware is actually running right now (detected on open, so
        # it reflects anything the Steam/Decky plugin applied behind our back).
        if self.store.active:
            pyxel.text(6, 26, "Running now: %s" % self.store.active, OK)
        else:
            pyxel.text(6, 26, "Running now: custom (no saved profile matches)", WARN)
        names = self.names()
        y = 40
        if not names:
            pyxel.text(10, y, "No profiles yet. Press X to create one.", FG)
        for i, n in enumerate(names):
            mark = ">" if i == self.prof_idx else " "
            tag = " <running>" if n == self.store.active else ""
            col = FG if i == self.prof_idx else DIM
            pyxel.text(10, y, "%s%s%s" % (mark, n, tag), col)
            y += 10
        pyxel.text(6, H - 40, self._sync_line(), self._sync_col())
        pyxel.text(6, H - 28, "A:Apply  Start:Save  X:New  Y:Rename", DIM)
        pyxel.text(6, H - 18, "Select:Delete  B:Quit  L/R:tabs  (<running>=applied now)", DIM)

    def _sync_line(self):
        if self.store.sync_status == C.SYNC_SYNCED:
            return "Steam sync: synced - profiles shared with the Decky plugin"
        if self.store.sync_status == C.SYNC_ABSENT:
            return "Steam sync: plugin not installed (using local profiles)"
        return "Steam sync: DESYNCED - %s" % (self.store.sync_reason or "format changed")

    def _sync_col(self):
        return {C.SYNC_SYNCED: OK, C.SYNC_ABSENT: DIM}.get(self.store.sync_status, BAD)

    def draw_cpu(self):
        pyxel.text(6, 16, "CPU CLOCKS  (edit '%s')" % (self.cur_name or "-"), HEAD)
        y = 30
        for i, pol in enumerate(self.policies):
            sel = i == self.cpu_idx
            mx = self.work.get("cpu_policy%d_max" % pol["num"], pol["cpuinfo_max"])
            mn = self.work.get("cpu_policy%d_min" % pol["num"], pol["cpuinfo_min"])
            col = FG if sel else DIM
            fmark_max = "[" if (sel and self.cpu_field == "max") else " "
            fmark_min = "[" if (sel and self.cpu_field == "min") else " "
            pyxel.text(10, y, "%s%-6s cpu%-5s max%s%4.2f< min%s%4.2f<" % (
                ">" if sel else " ", pol["label"], pol["cpus"],
                fmark_max, mx / 1e6, fmark_min, mn / 1e6), col)
            y += 10
        gsel = self.cpu_idx == len(self.policies)
        gov = self.work.get("governor") or "keep"
        pyxel.text(10, y + 4, "%sGovernor: %s" % (">" if gsel else " ", gov),
                   FG if gsel else DIM)
        pyxel.text(6, H - 28, "Up/Dn:row  Left/Right:value  X:max<->min", DIM)
        pyxel.text(6, H - 18, "values in GHz   L/R:tabs", DIM)

    def draw_gpu(self):
        pyxel.text(6, 16, "GPU CLOCKS  (edit '%s')" % (self.cur_name or "-"), HEAD)
        if not self.gpu:
            pyxel.text(10, 34, "No GPU devfreq node found.", BAD)
            return
        mx = self.work.get("gpu_max", self.gpu["avail"][-1] if self.gpu["avail"] else 0)
        mn = self.work.get("gpu_min", self.gpu["avail"][0] if self.gpu["avail"] else 0)
        rows = [("Max", mx, 0), ("Min", mn, 1)]
        y = 36
        for label, val, idx in rows:
            sel = self.gpu_idx == idx
            pyxel.text(14, y, "%s%-4s %4d MHz" % (
                ">" if sel else " ", label, val // 1000000), FG if sel else DIM)
            y += 12
        pyxel.text(14, y + 6, "cur %s MHz   gov %s" % (
            (self.gpu["cur"] or 0) // 1000000, self.gpu["governor"]), DIM)
        pyxel.text(6, H - 18, "Up/Dn:row  Left/Right:value   L/R:tabs", DIM)

    def draw_driver(self):
        pyxel.text(6, 16, "GPU DRIVER  (Mesa Turnip / Vulkan)", HEAD)
        if not self.drv_avail:
            pyxel.text(10, 34, "gpu-driver not available on this device.", BAD)
            return
        # Scope selector (Default / per-system). Left/Right cycles it.
        scope_name = DRIVER_SCOPES[self.drv_scope_idx][0]
        cur = self._scope_current()
        cur_txt = cur if cur else "(use default: %s)" % self.drv_default
        pyxel.text(6, 25, "Scope:  < %s >" % scope_name, HEAD)
        pyxel.text(6, 34, "uses: %s" % cur_txt, OK)
        rows = self.drv_rows
        y = 46
        if not rows:
            pyxel.text(10, y, "No drivers. Press X to fetch the online catalog.", FG)
        for i, r in enumerate(rows):
            if y > H - 44:
                break
            sel = i == self.drv_idx
            mark = ">" if sel else " "
            fav = "*" if r["fav"] else " "
            label = ("stock  Mesa %s" % r["ver"]) if r["id"] == "stock" \
                else "%s  Mesa %s" % (r["id"], r["ver"])
            # mark the driver assigned to the CURRENT scope
            here = " <-- this scope" if (r["installed"] and cur and r["id"] == cur) else ""
            defl = " [global default]" if (r["installed"] and r["id"] == self.drv_default) else ""
            state = "" if r["installed"] else "  [download]"
            pyxel.text(10, y, "%s%s%s%s%s%s" % (mark, fav, label, here, defl, state),
                       FG if sel else DIM)
            y += 10
        pyxel.text(6, H - 38, "L/R:scope  Up/Dn:driver  A:assign to scope (installs if needed)", DIM)
        pyxel.text(6, H - 28, "Y:favorite  X:refresh catalog  Select:clear this scope", DIM)
        pyxel.text(6, H - 18, "Per-process: a bad driver crashes the game, not the UI.  B:back", DIM)

    def draw_fan(self):
        mode = self.work.get("fan_mode", "auto")
        pyxel.text(6, 16, "FAN  (edit '%s')" % (self.cur_name or "-"), HEAD)
        msel = self.fan_idx == 0
        pyxel.text(10, 28, "%sMode: %s" % (">" if msel else " ", mode),
                   FG if msel else DIM)
        if mode == "auto":
            pyxel.text(10, 44, "System fan (cooling.profile=moderate).", DIM)
            pyxel.text(10, 54, "Switch to 'curve' to share a custom curve", DIM)
            pyxel.text(10, 62, "with the Steam plugin via fancontrol.conf.", DIM)
        elif mode == "fixed":
            fsel = self.fan_idx == 1
            pwm = A._clamp_pwm(self.work.get("fan_pwm", 0))
            pyxel.text(10, 46, "%sSpeed: %3d%%" % (
                ">" if fsel else " ", pwm * 100 // C.PWM_MAX), FG if fsel else DIM)
            self._bar(70, 46, pwm * 100 // C.PWM_MAX)
        else:
            self._draw_curve()
        pyxel.text(6, H - 28, "Up/Dn:row Left/Right:value X:temp<->pwm", DIM)
        pyxel.text(6, H - 18, "A:add point  Y:del point   L/R:tabs", DIM)

    def _draw_curve(self):
        c = self._curve()
        gx, gy, gw, gh = 200, 26, 150, 120
        pyxel.rectb(gx, gy, gw, gh, DIM)
        # axes labels
        pyxel.text(gx, gy + gh + 2, "0C", DIM)
        pyxel.text(gx + gw - 18, gy + gh + 2, "120C", DIM)
        # plot curve
        pts = sorted(zip(c["temps"], c["speeds"]))
        prev = None
        for t, s in pts:
            px = gx + int(gw * min(t, 120000) / 120000.0)
            py = gy + gh - int(gh * min(s, C.PWM_MAX) / float(C.PWM_MAX))
            if prev:
                pyxel.line(prev[0], prev[1], px, py, OK)
            pyxel.circ(px, py, 1, FG)
            prev = (px, py)
        # list of points (below the Mode row so they don't overlap it)
        pyxel.text(10, 42, "Points:", DIM)
        y = 52
        for i in range(len(c["temps"])):
            sel = self.fan_idx == i + 1
            tcol = SEL if (sel and self.fan_field == "temp") else (FG if sel else DIM)
            scol = SEL if (sel and self.fan_field == "pwm") else (FG if sel else DIM)
            pyxel.text(10, y, "%s" % (">" if sel else " "), FG if sel else DIM)
            pyxel.text(18, y, "%3dC" % (c["temps"][i] // 1000), tcol)
            pyxel.text(50, y, "%3d%%" % (c["speeds"][i] * 100 // C.PWM_MAX), scol)
            y += 10

    def _bar(self, x, y, pct):
        pyxel.rectb(x, y, 102, 6, DIM)
        pyxel.rect(x + 1, y + 1, max(0, min(100, pct)), 4, OK)

    def draw_monitor(self):
        now = time.time()
        if now - self._mon_last > 0.5:
            self._mon_last = now
            self.policies = hw.list_cpu_policies()
            self.gpu = hw.find_gpu()
            self._mon = {"zones": hw.thermal_zones(), "rpm": hw.fan_rpm()}
        pyxel.text(6, 16, "MONITOR (live)", HEAD)
        y = 28
        for pol in self.policies:
            pyxel.text(10, y, "%-6s cpu%-5s %4.2f GHz" % (
                pol["label"], pol["cpus"], (pol["cur"] or 0) / 1e6), FG)
            y += 9
        if self.gpu:
            pyxel.text(10, y, "GPU %4d MHz  gov %s" % (
                (self.gpu["cur"] or 0) // 1000000, self.gpu["governor"]), FG)
            y += 11
        # temps column on the right
        yy = 28
        mt = 0
        for t, mc in self._mon.get("zones", [])[:20]:
            mt = max(mt, mc)
            pyxel.text(200, yy, "%-9s %4.1fC" % (t[:9], mc / 1000.0), DIM)
            yy += 9
        pyxel.text(10, y + 4, "MAX %4.1f C   FAN %s rpm" % (
            mt / 1000.0, self._mon.get("rpm")), WARN if mt > 85000 else OK)
        pyxel.text(6, H - 16, "B:Quit   L/R:tabs", DIM)

    def _draw_toast(self):
        if self.toast and time.time() - self.toast_t < 2.5:
            w = len(self.toast) * 4 + 8
            pyxel.rect((W - w) // 2, H - 56, w, 10, 0)
            pyxel.text((W - w) // 2 + 4, H - 53, self.toast, HEAD)

    def _draw_desync(self):
        pyxel.rect(16, 50, W - 32, H - 110, 0)
        pyxel.rectb(16, 50, W - 32, H - 110, BAD)
        pyxel.text(26, 58, "STEAM PLUGIN SYNC LOST", BAD)
        msg = [
            "The Steam (Decky) plugin's profile format has",
            "changed, so the two tools can no longer share",
            "profiles automatically.",
            "",
            "Your ROCKNIX profiles are safe and still work.",
            "We will NOT touch the plugin's file while this",
            "lasts. Sync resumes automatically when a",
            "compatible plugin version is detected.",
            "",
            "reason: %s" % (self.store.sync_reason or "format changed"),
        ]
        for i, line in enumerate(msg):
            pyxel.text(26, 72 + i * 10, line, FG if i < 9 else DIM)
        pyxel.text(26, H - 70, "A/B: OK (don't show again for this change)", HEAD)

    def _draw_confirm(self, text):
        pyxel.rect(40, 90, W - 80, 50, 0)
        pyxel.rectb(40, 90, W - 80, 50, FG)
        pyxel.text(52, 104, text, FG)
        pyxel.text(52, 122, "A: yes    B: no", HEAD)


if __name__ == "__main__":
    try:
        App()
    except Exception as exc:  # never die silently on device
        C.log("UI crashed: %s" % exc)
        raise
