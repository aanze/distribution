# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# SteamGridDB art fetcher for EmulationStation gamelists.
#
# Pulls vertical cover (grid 600x900), hero (16:9 backdrop) and logo for each
# game in a system and wires them into that system's gamelist.xml media slots:
#     cover -> <image>   (theme binds {game:image}  = the capsule)
#     hero  -> <fanart>  (theme binds {game:fanart} = the Steam hero backdrop)
#     logo  -> <marquee> (theme binds {game:wheel}/{game:marquee} = logo)
#
# Stdlib only (urllib) so it runs on the device's system python3 with no venv.
# This is the headless backend; the Pyxel Theme Manager GUI will call it.

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

API_BASE = "https://www.steamgriddb.com/api/v2"
ROMS_ROOT = "/storage/roms"
CONFIG_FILE = "/storage/.config/themecfg/config"

# Systems whose games don't live under /storage/roms/<system>.
SYSTEM_DIRS = {
    # Steam games are .desktop launchers in the XDG applications dir.
    "steam": "/storage/.local/share/applications",
}
# When scanning a dir with no gamelist, only treat these extensions as games.
SCAN_EXTS = {
    "steam": (".desktop",),
}


def system_dir(system):
    return SYSTEM_DIRS.get(system, os.path.join(ROMS_ROOT, system))


# Writable dir for per-category background heroes (theme reads it first).
BG_DIR = "/storage/.config/themecfg/bg"

# Flagship game per platform -> its SteamGridDB HERO becomes the category
# background in the system view. Systems not listed keep the gradient fallback.
FLAGSHIP_BG = {
    "switch": "The Legend of Zelda Tears of the Kingdom",
    "ps3": "The Last of Us",
    "ps2": "God of War II",
    "psp": "God of War Ghost of Sparta",
    "psx": "Final Fantasy VII",
    "psvita": "Uncharted Golden Abyss",
    "n64": "Super Mario 64",
    "snes": "Super Mario World",
    "nes": "Super Mario Bros 3",
    "gc": "Metroid Prime",
    "wii": "Super Mario Galaxy",
    "wiiu": "Super Mario 3D World",
    "3ds": "The Legend of Zelda A Link Between Worlds",
    "nds": "Mario Kart DS",
    "gba": "Metroid Fusion",
    "gb": "Pokemon Red",
    "gbc": "The Legend of Zelda Oracle of Seasons",
    "genesis": "Sonic the Hedgehog 2",
    "megadrive": "Sonic the Hedgehog 2",
    "dreamcast": "Sonic Adventure 2",
    "saturn": "Nights into Dreams",
    "mastersystem": "Sonic the Hedgehog",
    "arcade": "Metal Slug 3",
    "mame": "Metal Slug 3",
    "neogeo": "Metal Slug",
    "pcengine": "Castlevania Rondo of Blood",
    "steam": "Half-Life 2",
    "xbox": "Halo Combat Evolved",
}

# Non-game launchers that should never get scraped art (utility entries).
SKIP_TITLES = {
    "desktop", "virtual display", "steam big picture", "steam",
    "retroarch", "ports", "open menu", "moonlight",
}

# media kind -> (sgdb endpoint segment, gamelist tag, subdir, default ext)
KINDS = {
    "cover": ("grids", "image", "images", "png"),
    "hero": ("heroes", "fanart", "media", "jpg"),
    "logo": ("logos", "marquee", "media", "png"),
}


# --------------------------------------------------------------------------- #
# config / http
# --------------------------------------------------------------------------- #
def read_api_key():
    key = os.environ.get("SGDB_API_KEY", "").strip()
    if key:
        return key
    try:
        with open(CONFIG_FILE, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("SGDB_API_KEY"):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


def api_get(path, key, params=None):
    url = API_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + key,
        "User-Agent": "rocknix-themecfg/0.1",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            raise SystemExit("ERROR: SteamGridDB rejected the API key (401). "
                             "Set a valid key in %s or $SGDB_API_KEY." % CONFIG_FILE)
        if exc.code == 404:
            return None
        sys.stderr.write("  http %s for %s\n" % (exc.code, url))
        return None
    except (urllib.error.URLError, TimeoutError) as exc:
        sys.stderr.write("  net error: %s\n" % exc)
        return None


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "rocknix-themecfg/0.1"})
    with urllib.request.urlopen(req, timeout=30) as resp, open(dest, "wb") as out:
        out.write(resp.read())


# --------------------------------------------------------------------------- #
# game discovery
# --------------------------------------------------------------------------- #
_PAREN = re.compile(r"[\(\[].*?[\)\]]")        # (USA), [!], (Disc 1) ...
_NOISE = re.compile(r"\b(rev|disc|disk|track)\b.*$", re.I)


def clean_title(name):
    name = _PAREN.sub("", name)
    name = _NOISE.sub("", name)
    name = name.replace("_", " ").replace(".", " ")
    return re.sub(r"\s+", " ", name).strip()


def gamelist_path(system):
    return os.path.join(system_dir(system), "gamelist.xml")


def load_games(system):
    """Return (tree, root, [(element, stem, term)]). Reads the system's
    gamelist.xml if present and merges in rom files on disk that aren't listed
    yet. Disk scan is limited to SCAN_EXTS[system] when defined (e.g. only
    .desktop for steam) so binaries/DLLs next to the games are never picked up."""
    gl = gamelist_path(system)
    rom_dir = system_dir(system)
    scan_exts = SCAN_EXTS.get(system)

    if os.path.isfile(gl):
        tree = ET.parse(gl)
        root = tree.getroot()
    else:
        root = ET.Element("gameList")
        tree = ET.ElementTree(root)

    by_path = {}
    for g in root.findall("game"):
        p = g.findtext("path") or ""
        if p:
            by_path[os.path.normpath(p)] = g

    # Only scan disk to build the list when we have an extension allowlist
    # (e.g. steam=.desktop) or there's no gamelist at all. If a curated
    # gamelist already exists (ps3/switch/etc.), trust it and don't sweep in
    # stray files like PS3UPDAT or gamelist.xml.
    if (scan_exts or not os.path.isfile(gl)) and os.path.isdir(rom_dir):
        for entry in sorted(os.listdir(rom_dir)):
            full = os.path.join(rom_dir, entry)
            if not os.path.isfile(full) or entry.startswith(".") or entry == "gamelist.xml":
                continue
            if scan_exts and os.path.splitext(entry)[1].lower() not in scan_exts:
                continue
            rel = "./" + entry
            if os.path.normpath(rel) in by_path or os.path.normpath(full) in by_path:
                continue
            g = ET.SubElement(root, "game")
            ET.SubElement(g, "path").text = rel
            by_path[os.path.normpath(rel)] = g

    out = []
    for g in root.findall("game"):
        name = g.findtext("name")
        stem = os.path.splitext(os.path.basename(g.findtext("path") or ""))[0]
        term = clean_title(name or stem)
        if term:
            out.append((g, stem, term))
    return tree, root, out


def steam_appid(stem, game_elem):
    """Steam roms often encode the appid; prefer exact lookup when we can."""
    m = re.search(r"(\d{5,7})", stem)
    return m.group(1) if m else None


# --------------------------------------------------------------------------- #
# fetch
# --------------------------------------------------------------------------- #
def find_game_id(term, key):
    data = api_get("/search/autocomplete/" + urllib.parse.quote(term), key)
    if not data or not data.get("data"):
        return None, None
    first = data["data"][0]
    return first["id"], first.get("name", term)


# Official Steam store assets (CDN by appid) - used when SteamGridDB has no
# community art for a game (0 grids/heroes/logos but it's a Steam title).
STEAM_CDN = "https://steamcdn-a.akamaihd.net/steam/apps/%s/%s"
STEAM_ASSET = {"cover": "library_600x900.jpg", "hero": "library_hero.jpg",
               "logo": "logo.png"}


def steam_appid_for_sgdb(sgdb_id, key):
    """The linked Steam appid for a SteamGridDB game id (if it's a Steam game)."""
    d = api_get("/games/id/%s" % sgdb_id, key, {"platformdata": "steam"})
    try:
        return d["data"]["external_platform_data"]["steam"][0]["id"]
    except (KeyError, TypeError, IndexError):
        return None


def first_asset_url(kind, by, ident, key):
    seg = KINDS[kind][0]
    params = {"dimensions": "600x900", "types": "static"} if kind == "cover" else None
    data = api_get("/%s/%s/%s" % (seg, by, ident), key, params)
    items = (data or {}).get("data") or []
    if not items and params:
        # no grid in the exact 600x900 static spec -> accept any grid
        data = api_get("/%s/%s/%s" % (seg, by, ident), key)
        items = (data or {}).get("data") or []
    if items:
        return items[0].get("url")
    # fallback: official Steam store asset (header/capsule/hero/logo by appid)
    appid = ident if by == "steam" else steam_appid_for_sgdb(ident, key)
    if appid and kind in STEAM_ASSET:
        return STEAM_CDN % (appid, STEAM_ASSET[kind])
    return None


def set_media(game_elem, tag, rel_path):
    el = game_elem.find(tag)
    if el is None:
        el = ET.SubElement(game_elem, tag)
    el.text = rel_path


def fetch_system(system, key, kinds, limit=0, overwrite=False, dry=False):
    tree, root, games = load_games(system)
    rom_dir = system_dir(system)
    print("system '%s': %d games" % (system, len(games)))
    done = 0
    for game_elem, stem, term in games:
        if limit and done >= limit:
            break
        if term.lower() in SKIP_TITLES:
            print("  - %-40s skipped (not a game)" % term[:40])
            continue
        # resolve the SGDB game id once (steam exact id, else name search)
        appid = steam_appid(stem, game_elem) if system == "steam" else None
        if appid:
            by, ident, label = "steam", appid, term
        else:
            gid, matched = find_game_id(term, key)
            if not gid:
                print("  ? %-40s no match" % term[:40])
                continue
            by, ident, label = "game", gid, matched
        print("  > %-40s -> %s" % (term[:40], label))

        for kind in kinds:
            tag, subdir, ext = KINDS[kind][1], KINDS[kind][2], KINDS[kind][3]
            dest = os.path.join(rom_dir, subdir, "%s-%s.%s" % (stem, kind, ext))
            rel = "./%s/%s-%s.%s" % (subdir, stem, kind, ext)
            if os.path.exists(dest) and not overwrite:
                set_media(game_elem, tag, rel)
                continue
            url = first_asset_url(kind, by, ident, key)
            if not url:
                continue
            if dry:
                print("      [dry] %s <- %s" % (kind, url))
            else:
                try:
                    download(url, dest)
                    set_media(game_elem, tag, rel)
                    print("      %s ok" % kind)
                except Exception as exc:  # noqa: BLE001
                    sys.stderr.write("      %s failed: %s\n" % (kind, exc))
            time.sleep(0.1)  # be gentle on the API
        done += 1

    if not dry:
        _indent(root)
        tree.write(gamelist_path(system), encoding="UTF-8", xml_declaration=True)
        print("wrote %s" % gamelist_path(system))


def fetch_background(system, key, overwrite=False, dry=False):
    """Pull the flagship game's HERO for a platform and save it as that
    category's background (BG_DIR/<theme>.jpg). The theme reads BG_DIR first."""
    term = FLAGSHIP_BG.get(system)
    if not term:
        print("bg '%s': no flagship mapping, keeps gradient" % system)
        return
    dest = os.path.join(BG_DIR, "%s.jpg" % system)
    if os.path.exists(dest) and not overwrite:
        print("bg '%s': already set" % system)
        return
    gid, matched = find_game_id(term, key)
    if not gid:
        print("bg '%s': no SGDB match for '%s'" % (system, term))
        return
    url = first_asset_url("hero", "game", gid, key)
    if not url:
        print("bg '%s': no hero for '%s'" % (system, matched))
        return
    if dry:
        print("bg '%s' [dry] <- %s (%s)" % (system, url, matched))
        return
    try:
        download(url, dest)
        print("bg '%s' <- %s" % (system, matched))
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write("bg '%s' failed: %s\n" % (system, exc))


# --------------------------------------------------------------------------- #
# backend API for the Theme Manager GUI (manual art re-pick, like Decky SGDB)
# --------------------------------------------------------------------------- #
def search_candidates(term, key, limit=10):
    """Return [(sgdb_id, name)] for a free-text query (the picker list)."""
    data = api_get("/search/autocomplete/" + urllib.parse.quote(term), key)
    if not data or not data.get("data"):
        return []
    return [(g["id"], g.get("name", "?")) for g in data["data"][:limit]]


def cover_url(sgdb_id, key):
    """First static 600x900 cover URL for a game (for the GUI preview)."""
    return first_asset_url("cover", "game", sgdb_id, key)


def hero_url(sgdb_id, key):
    return first_asset_url("hero", "game", sgdb_id, key)


def list_games_status(system):
    """Return [{stem,name,image,fanart,marquee}] for games whose ROM still
    exists on disk (skips stale gamelist entries for removed games), flagging
    which art slots are populated. De-duplicated by stem."""
    _, _, games = load_games(system)
    rom_dir = system_dir(system)
    out, seen = [], set()
    for g, stem, _term in games:
        path = g.findtext("path") or ""
        full = path if os.path.isabs(path) else os.path.join(rom_dir, path)
        if path and not os.path.exists(full):
            continue                      # removed game -> skip stale entry
        if stem in seen:
            continue
        seen.add(stem)
        out.append({
            "stem": stem,
            "name": (g.findtext("name") or stem),
            "image": bool(g.findtext("image")),
            "fanart": bool(g.findtext("fanart")),
            "marquee": bool(g.findtext("marquee")),
        })
    return out


def apply_art(system, stem, sgdb_id, key, kinds=None):
    """Download a SPECIFIC SteamGridDB game's art for one game (matched by
    stem) and wire it into the gamelist. This is the manual override the GUI
    calls after the user picks the right title. Returns True on success."""
    kinds = kinds or list(KINDS.keys())
    tree, root, games = load_games(system)
    target = next((g for g, s, _t in games if s == stem), None)
    if target is None:
        return False
    rom_dir = system_dir(system)
    ok = False
    for kind in kinds:
        tag, subdir, ext = KINDS[kind][1], KINDS[kind][2], KINDS[kind][3]
        url = first_asset_url(kind, "game", sgdb_id, key)
        if not url:
            continue
        dest = os.path.join(rom_dir, subdir, "%s-%s.%s" % (stem, kind, ext))
        rel = "./%s/%s-%s.%s" % (subdir, stem, kind, ext)
        try:
            download(url, dest)
            set_media(target, tag, rel)
            ok = True
        except Exception as exc:  # noqa: BLE001
            sys.stderr.write("apply %s/%s %s failed: %s\n" % (system, stem, kind, exc))
    if ok:
        _indent(root)
        tree.write(gamelist_path(system), encoding="UTF-8", xml_declaration=True)
    return ok


def _indent(elem, level=0):
    pad = "\n" + "\t" * level
    if len(elem):
        if not (elem.text or "").strip():
            elem.text = pad + "\t"
        for child in elem:
            _indent(child, level + 1)
        if not (child.tail or "").strip():
            child.tail = pad
    if level and not (elem.tail or "").strip():
        elem.tail = pad
