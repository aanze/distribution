#!/usr/bin/env python3
"""DUCKTALE steam-shortcuts: mirror ES sections into Steam non-Steam shortcuts.

Sections: /storage/roms/ps3 (*.ps3 disc folders via the native-RPCS3 wrapper)
and /storage/roms/geforcenow (*.sh launchers via the generic app wrapper).
Rebuilds shortcuts.vdf preserving every foreign entry, installs the
EmulationStation-scraped cover/hero/logo as Steam grid art. Rerunnable after
adding/removing games. Refuses to run while Steam is up (Steam rewrites
shortcuts.vdf from memory when it exits).
"""
import os
import shutil
import struct
import time
import zlib
from xml.etree import ElementTree

USERDATA = "/storage/.steam/steam/userdata"
MARKER = "ducktale-ps3"          # DevkitGameID tag identifying our entries

SECTIONS = [
    {"dir": "/storage/roms/ps3", "ext": ".ps3", "dirs_only": True,
     "wrapper": "/storage/.config/steam-shortcuts/ps3-launch.sh", "tag": "PS3"},
    {"dir": "/storage/roms/geforcenow", "ext": ".sh", "dirs_only": False,
     "wrapper": "/storage/.config/steam-shortcuts/app-launch.sh", "tag": "Cloud"},
]


def steam_running():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                cmd = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        if "steam.sh" in cmd or "steamwebhelper" in cmd:
            return True
    return False


# ---------------------------------------------------------------- binary VDF
def parse_kv(data, pos):
    obj = {}
    while True:
        t = data[pos]
        if t == 0x08:
            return obj, pos + 1
        pos += 1
        end = data.index(b"\x00", pos)
        key = data[pos:end].decode("utf-8", "replace")
        pos = end + 1
        if t == 0x00:
            val, pos = parse_kv(data, pos)
        elif t == 0x01:
            end = data.index(b"\x00", pos)
            val = data[pos:end].decode("utf-8", "replace")
            pos = end + 1
        elif t == 0x02:
            val = struct.unpack_from("<i", data, pos)[0]
            pos += 4
        else:
            raise ValueError("bad vdf type 0x%02x at %d" % (t, pos))
        obj[key] = val


def ser_kv(obj):
    out = bytearray()
    for k, v in obj.items():
        kb = str(k).encode("utf-8")
        if isinstance(v, dict):
            out += b"\x00" + kb + b"\x00" + ser_kv(v)
        elif isinstance(v, int):
            out += b"\x02" + kb + b"\x00" + struct.pack("<i", v)
        else:
            out += b"\x01" + kb + b"\x00" + str(v).encode("utf-8") + b"\x00"
    out += b"\x08"
    return bytes(out)


# ---------------------------------------------------------------- game scan
def scan_section(sec):
    """-> list of (name, target, cover, stem, sec)"""
    root = sec["dir"]
    names = {}   # basename -> (name, image-path); duplicates collapse here
    try:
        tree = ElementTree.parse(os.path.join(root, "gamelist.xml"))
        for g in tree.findall(".//game"):
            p = os.path.basename((g.findtext("path") or "").strip())
            if not p.endswith(sec["ext"]):
                continue
            img = (g.findtext("image") or "").strip()
            img = os.path.normpath(os.path.join(root, img)) if img else ""
            if p not in names or (img and os.path.isfile(img)):
                names[p] = ((g.findtext("name") or "").strip(), img)
    except (OSError, ElementTree.ParseError):
        pass
    games = []
    for entry in sorted(os.listdir(root)):
        full = os.path.join(root, entry)
        if not entry.endswith(sec["ext"]):
            continue
        if sec["dirs_only"] != os.path.isdir(full):
            continue
        name, img = names.get(entry, ("", ""))
        name = name or entry[:-len(sec["ext"])]
        cover = img if img and os.path.isfile(img) else ""
        stem = ""
        if cover:
            b = os.path.basename(cover)
            for suf in ("-cover.png", "-cover.jpg"):
                if b.endswith(suf):
                    stem = b[:-len(suf)]
        games.append((name, full, cover, stem, sec))
    return games


def shortcut_appid(exe, name):
    return (zlib.crc32((exe + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def make_entry(name, target, cover, sec):
    exe = '"%s" "%s"' % (sec["wrapper"], target)
    uapp = shortcut_appid(exe, name)
    return uapp, {
        "appid": uapp - 2**32,      # stored as signed int32
        "appname": name,
        "Exe": exe,
        "StartDir": '"%s/"' % sec["dir"],
        "icon": cover,
        "ShortcutPath": "",
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": MARKER,
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "tags": {"0": sec["tag"]},
    }


def install_art(grid_dir, uapp, cover, stem, sec):
    os.makedirs(grid_dir, exist_ok=True)
    hero = logo = ""
    for d in ("media", "images"):
        for ext in (".jpg", ".png"):
            p = os.path.join(sec["dir"], d, "%s-hero%s" % (stem, ext))
            if not hero and os.path.isfile(p):
                hero = p
            p = os.path.join(sec["dir"], d, "%s-logo%s" % (stem, ext))
            if not logo and os.path.isfile(p):
                logo = p
    done = []
    if cover:
        shutil.copyfile(cover, os.path.join(
            grid_dir, "%dp%s" % (uapp, os.path.splitext(cover)[1])))
        done.append("cover")
    if hero:
        ext = os.path.splitext(hero)[1]
        shutil.copyfile(hero, os.path.join(grid_dir, "%d_hero%s" % (uapp, ext)))
        shutil.copyfile(hero, os.path.join(grid_dir, "%d%s" % (uapp, ext)))
        done.append("hero+wide")
    if logo:
        shutil.copyfile(logo, os.path.join(
            grid_dir, "%d_logo%s" % (uapp, os.path.splitext(logo)[1])))
        done.append("logo")
    return done


def main():
    if steam_running():
        raise SystemExit("Steam is running - close it first (it would "
                         "overwrite shortcuts.vdf on exit).")
    games = []
    for sec in SECTIONS:
        if os.path.isdir(sec["dir"]):
            games.extend(scan_section(sec))
    if not games:
        raise SystemExit("no games found in any section")
    accounts = [d for d in os.listdir(USERDATA)
                if d.isdigit() and d != "0"
                and os.path.isdir(os.path.join(USERDATA, d, "config"))]
    if not accounts:
        raise SystemExit("no Steam account under %s" % USERDATA)
    for acc in accounts:
        cfg_dir = os.path.join(USERDATA, acc, "config")
        vdf_path = os.path.join(cfg_dir, "shortcuts.vdf")
        shortcuts = {}
        if os.path.isfile(vdf_path):
            data = open(vdf_path, "rb").read()
            if data:
                shortcuts = parse_kv(data, 0)[0].get("shortcuts", {})
            shutil.copy2(vdf_path, vdf_path + ".bak-" +
                         time.strftime("%Y%m%d-%H%M%S"))
        kept = [v for v in shortcuts.values()
                if isinstance(v, dict) and v.get("DevkitGameID") != MARKER]
        added = []
        for name, target, cover, stem, sec in games:
            uapp, entry = make_entry(name, target, cover, sec)
            kept.append(entry)
            art = install_art(os.path.join(cfg_dir, "grid"), uapp, cover,
                              stem, sec)
            added.append("%s [%s] (appid %d, art: %s)"
                         % (name, sec["tag"], uapp, "+".join(art) or "none"))
        out = ser_kv({"shortcuts": {str(i): e for i, e in enumerate(kept)}})
        tmp = vdf_path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(out)
        os.replace(tmp, vdf_path)
        print("account %s: %d foreign entr%s kept, %d added:"
              % (acc, len(kept) - len(added),
                 "y" if len(kept) - len(added) == 1 else "ies", len(added)))
        for line in added:
            print("  + " + line)


if __name__ == "__main__":
    main()
