#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Steamlike Theme Manager - Pyxel GUI (gamepad driven, full screen via sway).
# Runs under the gamepadcalibration Pyxel venv. Logic lives in the stdlib
# modules themecfg_settings (look) + sgdb_fetch (art). On exit the launcher
# restarts EmulationStation so theme changes take effect.

import os
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pyxel  # noqa: E402  (gamepadcalibration venv)

import themecfg_settings as S  # noqa: E402
import sgdb_fetch as F         # noqa: E402

W, H = 360, 240
BG, FG, DIM, HEAD, OK, BAD, WARN, SEL, ACC = 1, 7, 13, 10, 11, 8, 9, 6, 12
TABS = ["LOOK", "ART", "BACKGROUNDS", "STEAMGRIDDB", "ABOUT"]
KEY_FILE = "/storage/.config/themecfg/config"
RELOAD_FLAG = "/storage/.config/themecfg/.reload"
BG_SRC = "/storage/roms/_userdata/backgrounds"     # drop your images here
BG_DST = "/storage/.config/themecfg/bg"            # theme reads <theme>.jpg here
BG_PREV_W, BG_PREV_H = 200, 112                     # 16:9 preview

# candidate art preview (downloaded + ImageMagick-resized into a Pyxel bank)
PREV_BANK = 2
PREV_DIMS = {"cover": (104, 156), "hero": (150, 48)}   # blit sizes per kind
PREV_DL = "/tmp/tcfg_dl.png"
PREV_PNG = "/tmp/tcfg_prev.png"
PAL_PNG = "/tmp/tcfg_pal.png"
ERR_LOG = "/tmp/tcfg_err.log"


def _log(msg):
    try:
        with open(ERR_LOG, "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass


def build_palette_png():
    """Write a strip of Pyxel's current 16 colours so previews can be remapped
    onto exactly those colours -> load(incl_colors=False) never throws and the
    UI palette is never disturbed."""
    sw = []
    for i in range(16):
        try:
            sw.append("xc:#%06x" % (int(pyxel.colors[i]) & 0xFFFFFF))
        except Exception:  # noqa: BLE001
            break
    if not sw:
        return
    try:
        subprocess.run(["convert"] + sw + ["+append", PAL_PNG], check=True,
                       timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as exc:  # noqa: BLE001
        _log("palette png failed: %r" % exc)


def make_preview(url, kind):
    """Download art, resize, and remap onto Pyxel's palette (with dithering)."""
    w, h = PREV_DIMS[kind]
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "rocknix-themecfg"})
        with urllib.request.urlopen(req, timeout=12) as r, open(PREV_DL, "wb") as f:
            f.write(r.read())
        cmd = ["convert", PREV_DL, "-resize", "%dx%d!" % (w, h)]
        if os.path.exists(PAL_PNG):
            cmd += ["-dither", "FloydSteinberg", "-remap", PAL_PNG]
        cmd += ["PNG8:" + PREV_PNG]
        subprocess.run(cmd, check=True, timeout=12,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as exc:  # noqa: BLE001
        _log("make_preview failed: %r" % exc)
        return False


def make_local_preview(path, w, h):
    """Resize a local image (cover-fit) + remap to the palette for blt."""
    try:
        cmd = ["convert", path, "-resize", "%dx%d^" % (w, h),
               "-gravity", "center", "-extent", "%dx%d" % (w, h)]
        if os.path.exists(PAL_PNG):
            cmd += ["-dither", "FloydSteinberg", "-remap", PAL_PNG]
        cmd += ["PNG8:" + PREV_PNG]
        subprocess.run(cmd, check=True, timeout=12,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as exc:  # noqa: BLE001
        _log("local preview failed: %r" % exc)
        return False


def _K(*names):
    return [getattr(pyxel, n) for n in names if getattr(pyxel, n, None) is not None]


KU = _K("KEY_UP", "GAMEPAD1_BUTTON_DPAD_UP")
KD = _K("KEY_DOWN", "GAMEPAD1_BUTTON_DPAD_DOWN")
KL = _K("KEY_LEFT", "GAMEPAD1_BUTTON_DPAD_LEFT")
KR = _K("KEY_RIGHT", "GAMEPAD1_BUTTON_DPAD_RIGHT")
KA = _K("KEY_RETURN", "KEY_Z", "GAMEPAD1_BUTTON_A")
KB = _K("KEY_BACKSPACE", "KEY_X", "GAMEPAD1_BUTTON_B")
KX = _K("KEY_C", "GAMEPAD1_BUTTON_X")
KY = _K("KEY_V", "GAMEPAD1_BUTTON_Y")
KLB = _K("KEY_Q", "GAMEPAD1_BUTTON_LEFTSHOULDER")
KRB = _K("KEY_E", "GAMEPAD1_BUTTON_RIGHTSHOULDER")


def _p(keys, hold=0, rep=0):
    for k in keys:
        if pyxel.btnp(k, hold, rep) if hold else pyxel.btnp(k):
            return True
    return False


def UP(r=True): return _p(KU, *((14, 3) if r else (0, 0)))
def DOWN(r=True): return _p(KD, *((14, 3) if r else (0, 0)))
def LEFT(): return _p(KL, 18, 3)
def RIGHT(): return _p(KR, 18, 3)
def A_BTN(): return _p(KA)
def B_BTN(): return _p(KB)
def X_BTN(): return _p(KX)
def Y_BTN(): return _p(KY)
def L_BTN(): return _p(KLB)
def R_BTN(): return _p(KRB)


class Keyboard(object):
    ROWS = ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789 :-_."]

    def __init__(self, title, text, on_done):
        self.title, self.text, self.on_done = title, text, on_done
        self.cx = self.cy = 0

    def update(self):
        if UP(False):
            self.cy = (self.cy - 1) % len(self.ROWS)
        if DOWN(False):
            self.cy = (self.cy + 1) % len(self.ROWS)
        if LEFT():
            self.cx = (self.cx - 1) % len(self.ROWS[self.cy])
        if RIGHT():
            self.cx = (self.cx + 1) % len(self.ROWS[self.cy])
        if A_BTN():
            self.text += self.ROWS[self.cy][self.cx]
        if X_BTN():
            self.text = self.text[:-1]
        if Y_BTN():
            self.on_done(self.text.strip())
            return True
        if B_BTN():
            self.on_done(None)
            return True
        return False

    def draw(self):
        pyxel.rect(16, 30, W - 32, H - 60, 0)
        pyxel.rectb(16, 30, W - 32, H - 60, FG)
        pyxel.text(24, 38, self.title, HEAD)
        pyxel.rect(24, 50, W - 48, 10, BG)
        pyxel.text(28, 53, self.text + "_", FG)
        for ry, row in enumerate(self.ROWS):
            for rx, ch in enumerate(row):
                x, y = 28 + rx * 28, 76 + ry * 16
                if rx == self.cx and ry == self.cy:
                    pyxel.rect(x - 3, y - 2, 13, 11, SEL)
                pyxel.text(x, y, ch if ch != " " else "sp", FG)
        pyxel.text(24, H - 40, "A:type  X:del  Y:ok  B:cancel", DIM)


class App(object):
    def __init__(self):
        self.vals = S.load()
        self.systems = self._discover()
        # Background categories = the ES tabs. self.systems covers the
        # /storage/roms systems (+ steam); the favorites collection and the Tools
        # menu are tabs too but aren't rom dirs, so add them. The theme looks up
        # backgrounds by {system:theme}.jpg -> favorites.jpg / tools.jpg.
        self.bgcats = self.systems + [c for c in ("favorites", "tools")
                                      if c not in self.systems]
        self.tab = 0
        self.look_i = 0
        self.sys_i = 0
        self.game_i = 0
        self.games = []
        self.cands = None        # candidate list during re-pick
        self.cand_i = 0
        self.cand_stem = None
        self.prev_i = -1         # which candidate the loaded preview is for
        self.prev_ok = False
        self.prev_msg = "loading..."
        self.prev_kind = "cover"  # cover | hero  (toggle with X in picker)
        self.kbd = None
        self.toast = ""
        self.toast_t = 0
        self.dirty = False
        # backgrounds tab
        self.bgcat_i = 0
        self.bg_i = 0
        self.bg_prev_i = -1
        self.bg_prev_ok = False
        self.bg_files = self._scan_bg()
        try:
            os.makedirs(BG_DST, exist_ok=True)
            os.makedirs(BG_SRC, exist_ok=True)
        except OSError:
            pass
        self._load_games()
        try:
            os.remove(RELOAD_FLAG)
        except OSError:
            pass
        pyxel.init(W, H, title="Steamlike Theme Manager", fps=30,
                   quit_key=pyxel.KEY_NONE)
        build_palette_png()    # snapshot palette for preview remapping
        pyxel.run(self.update, self.draw)

    # -- helpers ----------------------------------------------------------- #
    @staticmethod
    def _discover():
        out = []
        try:
            for d in sorted(os.listdir(F.ROMS_ROOT)):
                if os.path.isfile(F.gamelist_path(d)):
                    out.append(d)
        except OSError:
            pass
        if "steam" not in out and os.path.isfile(F.gamelist_path("steam")):
            out.append("steam")
        return out or ["steam"]

    def _load_games(self):
        if not self.systems:
            self.games = []
            return
        sysname = self.systems[self.sys_i % len(self.systems)]
        try:
            self.games = F.list_games_status(sysname)
        except Exception:  # noqa: BLE001
            self.games = []
        self.game_i = 0

    def say(self, msg):
        self.toast, self.toast_t = msg, time.time()

    def _key(self):
        return F.read_api_key()

    def _quit(self):
        S.save(self.vals)
        if self.dirty:
            open(RELOAD_FLAG, "w").close()   # launcher restarts ES
        pyxel.quit()

    # -- update ------------------------------------------------------------ #
    def update(self):
        if self.kbd is not None:
            if self.kbd.update():
                self.kbd = None
            return
        if self.cands is not None:
            self._upd_cands()
            return
        if L_BTN():
            self.tab = (self.tab - 1) % len(TABS)
        if R_BTN():
            self.tab = (self.tab + 1) % len(TABS)
        [self.upd_look, self.upd_art, self.upd_bg,
         self.upd_sgdb, self.upd_about][self.tab]()

    def upd_look(self):
        n = len(S.SETTINGS)
        if UP():
            self.look_i = (self.look_i - 1) % n
        if DOWN():
            self.look_i = (self.look_i + 1) % n
        st = S.SETTINGS[self.look_i]
        cur = self.vals.get(st["key"], S.DEFAULTS[st["key"]])
        if LEFT():
            self.vals[st["key"]] = S.adjust(st, cur, -1)
            self.dirty = True
        if RIGHT():
            self.vals[st["key"]] = S.adjust(st, cur, +1)
            self.dirty = True
        if B_BTN():
            self._quit()

    def upd_art(self):
        if not self.systems:
            if B_BTN():
                self._quit()
            return
        if LEFT():
            self.sys_i = (self.sys_i - 1) % len(self.systems)
            self._load_games()
        if RIGHT():
            self.sys_i = (self.sys_i + 1) % len(self.systems)
            self._load_games()
        if self.games:
            if UP():
                self.game_i = (self.game_i - 1) % len(self.games)
            if DOWN():
                self.game_i = (self.game_i + 1) % len(self.games)
            g = self.games[self.game_i]
            if X_BTN():     # manual search by name
                self._search(g["name"], g["stem"])
            if A_BTN():     # auto re-fetch (best match on the name)
                self._auto_fetch(g)
        if B_BTN():
            self._quit()

    def _search(self, prefill, stem):
        def done(term):
            if not term:
                return
            key = self._key()
            if not key:
                self.say("Set a SteamGridDB key first (STEAMGRIDDB tab)")
                return
            self.say("searching...")
            try:
                self.cands = F.search_candidates(term, key, 10) or []
            except Exception:  # noqa: BLE001
                self.cands = []
            self.cand_i = 0
            self.cand_stem = stem
            self.prev_i = -1          # force preview load for the first result
            if not self.cands:
                self.cands = None
                self.say("No matches for '%s'" % term)
            else:
                self.say("%d match(es) - A to apply" % len(self.cands))
        self.kbd = Keyboard("Search game name", prefill, done)

    def _load_preview(self):
        self.prev_ok = False
        self.prev_msg = "loading..."
        self.prev_i = self.cand_i
        key = self._key()
        if not key:
            self.prev_msg = "no API key"
            return
        cid = self.cands[self.cand_i][0]
        try:
            url = F.hero_url(cid, key) if self.prev_kind == "hero" \
                else F.cover_url(cid, key)
        except Exception as exc:  # noqa: BLE001
            _log("url err: %r" % exc)
            url = None
        if not url:
            self.prev_msg = "no %s on SteamGridDB" % self.prev_kind
            return
        if not make_preview(url, self.prev_kind):
            self.prev_msg = "preview error"
            return
        try:
            # pre-remapped to the palette: maps cleanly, never clobbers the UI.
            pyxel.images[PREV_BANK].load(0, 0, PREV_PNG, incl_colors=False)
            self.prev_ok = True
        except Exception as exc:  # noqa: BLE001
            _log("pyxel load failed: %r" % exc)
            self.prev_msg = "preview error"

    def _upd_cands(self):
        if self.prev_i != self.cand_i:    # selection moved -> load its art
            self._load_preview()
        if UP():
            self.cand_i = (self.cand_i - 1) % len(self.cands)
        if DOWN():
            self.cand_i = (self.cand_i + 1) % len(self.cands)
        if X_BTN():                       # toggle cover <-> hero preview
            self.prev_kind = "hero" if self.prev_kind == "cover" else "cover"
            self.prev_i = -1              # force reload in this new kind
        if B_BTN():
            self.cands = None
            return
        if A_BTN():
            cid = self.cands[self.cand_i][0]
            key = self._key()
            self.say("downloading art...")
            try:
                ok = F.apply_art(self.systems[self.sys_i], self.cand_stem, cid, key)
            except Exception:  # noqa: BLE001
                ok = False
            self.cands = None
            self.dirty = self.dirty or ok
            self._load_games()
            self.say("art updated" if ok else "art fetch failed")

    def _auto_fetch(self, g):
        key = self._key()
        if not key:
            self.say("Set a SteamGridDB key first (STEAMGRIDDB tab)")
            return
        self.say("fetching...")
        try:
            cands = F.search_candidates(g["name"], key, 1)
            if cands:
                ok = F.apply_art(self.systems[self.sys_i], g["stem"], cands[0][0], key)
            else:
                ok = False
        except Exception:  # noqa: BLE001
            ok = False
        self.dirty = self.dirty or ok
        self._load_games()
        self.say("art updated" if ok else "no match / failed")

    # -- backgrounds tab --------------------------------------------------- #
    def _scan_bg(self):
        try:
            return sorted(f for f in os.listdir(BG_SRC)
                          if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp")))
        except OSError:
            return []

    def _load_bg_preview(self):
        self.bg_prev_ok = False
        self.bg_prev_i = self.bg_i
        if not self.bg_files:
            return
        path = os.path.join(BG_SRC, self.bg_files[self.bg_i])
        if make_local_preview(path, BG_PREV_W, BG_PREV_H):
            try:
                pyxel.images[PREV_BANK].load(0, 0, PREV_PNG, incl_colors=False)
                self.bg_prev_ok = True
            except Exception as exc:  # noqa: BLE001
                _log("bg preview load: %r" % exc)

    def upd_bg(self):
        cats = self.bgcats
        if LEFT() and cats:
            self.bgcat_i = (self.bgcat_i - 1) % len(cats)
        if RIGHT() and cats:
            self.bgcat_i = (self.bgcat_i + 1) % len(cats)
        if self.bg_files:
            if self.bg_prev_i != self.bg_i:
                self._load_bg_preview()
            if UP():
                self.bg_i = (self.bg_i - 1) % len(self.bg_files)
            if DOWN():
                self.bg_i = (self.bg_i + 1) % len(self.bg_files)
            if A_BTN():
                self._apply_bg()
            if X_BTN():
                self._clear_bg()
        if B_BTN():
            self._quit()

    def _apply_bg(self):
        cats = self.bgcats
        if not cats or not self.bg_files:
            return
        cat = cats[self.bgcat_i]
        src = os.path.join(BG_SRC, self.bg_files[self.bg_i])
        dst = os.path.join(BG_DST, cat + ".jpg")
        try:
            os.makedirs(BG_DST, exist_ok=True)
            subprocess.run(["convert", src, dst], check=True, timeout=20,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            alt = os.path.join(BG_DST, cat + ".png")
            if os.path.exists(alt):
                os.remove(alt)
            self.dirty = True
            self.say("background set for %s" % cat)
        except Exception as exc:  # noqa: BLE001
            _log("apply bg: %r" % exc)
            self.say("set failed")

    def _clear_bg(self):
        cat = self.bgcats[self.bgcat_i]
        n = 0
        for ext in (".jpg", ".png"):
            p = os.path.join(BG_DST, cat + ext)
            if os.path.exists(p):
                os.remove(p)
                n += 1
        self.dirty = self.dirty or n > 0
        self.say("background cleared" if n else "no custom background")

    def upd_sgdb(self):
        if A_BTN():
            self.kbd = Keyboard("SteamGridDB API key", self._key(), self._set_key)
        if Y_BTN() and self.systems:
            self._fetch_system()
        if B_BTN():
            self._quit()

    def _set_key(self, k):
        if k is None:
            return
        os.makedirs(os.path.dirname(KEY_FILE), exist_ok=True)
        with open(KEY_FILE, "w", encoding="utf-8") as fh:
            fh.write("SGDB_API_KEY=%s\n" % k)
        os.chmod(KEY_FILE, 0o600)
        self.say("API key saved")

    def _fetch_system(self):
        key = self._key()
        if not key:
            self.say("Set a SteamGridDB key first")
            return
        sysname = self.systems[self.sys_i]
        self.say("fetching all art for %s..." % sysname)
        try:
            F.fetch_system(sysname, key, list(F.KINDS.keys()))
            self.dirty = True
            self._load_games()
            self.say("done fetching %s" % sysname)
        except Exception:  # noqa: BLE001
            self.say("fetch failed")

    def upd_about(self):
        msg = getattr(self, "_rebuild_msg", None)
        if msg:                       # thread finished -> surface the result
            self.say(msg)
            self._rebuild_msg = None
        busy = getattr(self, "_rebuild_thr", None) and self._rebuild_thr.is_alive()
        if Y_BTN() and not busy:
            self._rebuild_covers()
        if B_BTN():
            if busy:
                self.say("rebuild in progress...")
            else:
                self._quit()

    def _rebuild_covers(self):
        """Regenerate Tools cover-cards from the icons (for newly-added tools).

        Runs ImageMagick in a background thread so the GUI stays responsive;
        the result is surfaced on the next frame via _rebuild_msg. New covers
        land in /storage/.config/themecfg/covers (overrides the shipped ones)."""
        import threading
        self.say("rebuilding tool covers...")
        self._rebuild_msg = None

        def work():
            try:
                import gen_tool_covers as G
                n = G.bake_covers()
                G.apply_covers()
                self.dirty = True     # ES reload on exit picks up the covers
                self._rebuild_msg = "rebuilt %d tool covers" % n
            except Exception:  # noqa: BLE001
                self._rebuild_msg = "rebuild failed"

        self._rebuild_thr = threading.Thread(target=work, daemon=True)
        self._rebuild_thr.start()

    # -- draw -------------------------------------------------------------- #
    def draw(self):
        pyxel.cls(BG)
        self._tabs()
        if self.cands is not None:
            self._draw_cands()        # full modal, replaces tab content
        else:
            [self.draw_look, self.draw_art, self.draw_bg,
             self.draw_sgdb, self.draw_about][self.tab]()
        if self.kbd is not None:
            self.kbd.draw()
        self._toast()

    def _tabs(self):
        pyxel.rect(0, 0, W, 11, 0)
        x = 4
        for i, t in enumerate(TABS):
            pyxel.text(x, 3, t, HEAD if i == self.tab else DIM)
            x += len(t) * 4 + 8
        pyxel.text(W - 36, 3, "L/R tabs", DIM)

    def draw_look(self):
        pyxel.text(6, 16, "APPEARANCE", HEAD)
        y = 30
        for i, st in enumerate(S.SETTINGS):
            sel = i == self.look_i
            cur = self.vals.get(st["key"], S.DEFAULTS[st["key"]])
            col = FG if sel else DIM
            pyxel.text(10, y, "%s%-16s" % (">" if sel else " ", st["label"]), col)
            vx = 150
            pyxel.text(vx, y, "< %s >" % S.display(st, cur) if sel
                       else "  %s" % S.display(st, cur), ACC if sel else DIM)
            # accent swatch preview
            y += 13
        pyxel.text(6, H - 26, "Up/Dn:pick  Left/Right:change", DIM)
        pyxel.text(6, H - 16, "B:save & exit (restarts ES)   L/R:tabs", DIM)

    def draw_art(self):
        if not self.systems:
            pyxel.text(6, 16, "No systems with a gamelist found.", WARN)
            return
        sysname = self.systems[self.sys_i]
        pyxel.text(6, 16, "ART:  < %s >  (%d)" % (sysname.upper(), len(self.games)),
                   HEAD)
        y = 30
        view = self.games[max(0, self.game_i - 8):][:12]
        base = max(0, self.game_i - 8)
        for off, g in enumerate(view):
            i = base + off
            sel = i == self.game_i
            flags = ("C" if g["image"] else "-") + ("H" if g["fanart"] else "-") \
                + ("L" if g["marquee"] else "-")
            col = FG if sel else DIM
            pyxel.text(10, y, "%s%-30s %s" % (">" if sel else " ",
                       g["name"][:30], flags), col)
            y += 10
        pyxel.text(6, H - 26, "L/R sys-or-tab  Up/Dn game  CHL=cover/hero/logo", DIM)
        pyxel.text(6, H - 16, "A:auto-fetch  X:search by name  B:save&exit", DIM)

    def draw_bg(self):
        cats = self.bgcats
        cat = cats[self.bgcat_i] if cats else "-"
        pyxel.text(6, 16, "BACKGROUND:  < %s >" % cat.upper(), HEAD)
        if not self.bg_files:
            pyxel.text(10, 40, "No images found in:", FG)
            pyxel.text(10, 52, BG_SRC, ACC)
            pyxel.text(10, 70, "Drop .jpg/.png files there, then reopen", DIM)
            pyxel.text(10, 80, "the Theme Manager.", DIM)
            pyxel.text(6, H - 16, "Left/Right:category  L/R:tabs  B:save&exit", DIM)
            return
        # file list (left)
        base = max(0, self.bg_i - 8)
        y = 34
        for off, f in enumerate(self.bg_files[base:][:12]):
            i = base + off
            sel = i == self.bg_i
            pyxel.text(10, y, "%s%s" % (">" if sel else " ", f[:30]),
                       FG if sel else DIM)
            y += 10
        # preview (right)
        px, py = W - BG_PREV_W - 16, 40
        pyxel.rectb(px - 1, py - 1, BG_PREV_W + 2, BG_PREV_H + 2, DIM)
        if self.bg_prev_ok:
            pyxel.blt(px, py, PREV_BANK, 0, 0, BG_PREV_W, BG_PREV_H)
        else:
            pyxel.text(px + 70, py + BG_PREV_H // 2, "loading...", DIM)
        pyxel.text(6, H - 26, "L/R cat  Up/Dn img  A:set  X:clear", DIM)
        pyxel.text(6, H - 16, "drop images in %s   B:save&exit" % BG_SRC, DIM)

    def draw_sgdb(self):
        pyxel.text(6, 16, "STEAMGRIDDB", HEAD)
        k = self._key()
        if k:
            pyxel.text(10, 34, "API key: set (%s...%s)" % (k[:4], k[-3:]), OK)
        else:
            pyxel.text(10, 34, "API key: NOT SET", BAD)
        pyxel.text(10, 50, "A: set / change API key", FG)
        sysname = self.systems[self.sys_i] if self.systems else "-"
        pyxel.text(10, 64, "Y: fetch ALL art for '%s'" % sysname, FG)
        pyxel.text(10, 78, "   (pick the system on the ART tab)", DIM)
        pyxel.text(10, 100, "Get a free key at steamgriddb.com", DIM)
        pyxel.text(10, 108, "-> Preferences -> API", DIM)
        pyxel.text(6, H - 16, "B:save & exit   L/R:tabs", DIM)

    def draw_about(self):
        pyxel.text(6, 16, "STEAMLIKE THEME MANAGER", HEAD)
        for i, line in enumerate([
                "Customise the Steam-style ROCKNIX theme.",
                "",
                "LOOK   - accent, shelf, scrim, toggles",
                "ART    - re-pick cover/hero/logo per game",
                "SGDB   - SteamGridDB API key + bulk fetch",
                "",
                "Changes apply on exit (ES restarts).",
                "Art comes from SteamGridDB; the theme",
                "binds cover->image hero->fanart logo->marquee.",
        ]):
            pyxel.text(10, 32 + i * 11, line, FG if line and i < 5 else DIM)
        pyxel.text(10, 32 + 10 * 11, "Y: rebuild Tools cover-cards", ACC)
        pyxel.text(10, 32 + 11 * 11, "   (run after adding new tools)", DIM)
        pyxel.text(6, H - 16, "Y:rebuild covers   B:save & exit   L/R:tabs", DIM)

    def _draw_cands(self):
        pyxel.rect(12, 20, W - 24, H - 30, 0)
        pyxel.rectb(12, 20, W - 24, H - 30, ACC)
        pyxel.text(18, 26, "Pick the right game:", HEAD)
        # names list on the left (fixed-width column, never under the preview)
        nw = 168
        y = 42
        for i, (_cid, name) in enumerate(self.cands[:14]):
            sel = i == self.cand_i
            if sel:
                pyxel.rect(16, y - 1, nw, 9, SEL)
            pyxel.text(18, y, name[:27], FG if sel else DIM)
            y += 10
        # art preview in a fixed zone on the right
        pw, ph = PREV_DIMS[self.prev_kind]
        px, py = 192, 42
        pyxel.text(px, 30, "PREVIEW: " + self.prev_kind.upper(), ACC)
        pyxel.rectb(px - 1, py - 1, pw + 2, ph + 2, DIM)
        if self.prev_ok:
            pyxel.blt(px, py, PREV_BANK, 0, 0, pw, ph)
        else:
            pyxel.text(px + 6, py + ph // 2, self.prev_msg, DIM)
        pyxel.text(18, H - 22, "A:apply all  X:cover/hero  Up/Dn:browse  B:cancel", DIM)

    def _toast(self):
        if self.toast and time.time() - self.toast_t < 3:
            w = len(self.toast) * 4 + 8
            pyxel.rect((W - w) // 2, H - 44, w, 10, 0)
            pyxel.rectb((W - w) // 2, H - 44, w, 10, ACC)
            pyxel.text((W - w) // 2 + 4, H - 41, self.toast, HEAD)


if __name__ == "__main__":
    App()
