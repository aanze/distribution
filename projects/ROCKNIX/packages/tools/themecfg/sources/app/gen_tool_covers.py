#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Tools cover-cards for the steamlike cover-shelf: render the Tools section's
# square icons as 2:3 "cover cards" so they look like game capsules instead of
# small square icons with the selection rectangle showing behind them.
#
# Two modes:
#   --apply  (default)  Re-point the Tools gamelist <image> at pre-baked cover
#                       PNGs. Pure-stdlib XML rewrite, NO ImageMagick -> fast and
#                       can NOT hang. A common autostart script runs this every
#                       boot, AFTER 001-sync-modules (which rsyncs the pristine
#                       gamelist into /storage and reverts our edits each boot).
#   --bake              (Re)generate the cover PNGs from the icons with
#                       ImageMagick into the writable user dir, then --apply.
#                       Used by the Theme Manager "rebuild tool covers" action
#                       when new tools / icons are added.
#
# Covers ship pre-baked & read-only in SYS_COVERS (so first boot already has
# them, no on-device ImageMagick at boot). A user rebuild writes to USER_COVERS
# which takes precedence, so custom/new covers override the shipped ones.

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

MOD = "/storage/.config/modules"
GAMELIST = os.path.join(MOD, "gamelist.xml")
USER_COVERS = "/storage/.config/themecfg/covers"   # writable (GUI rebuild)
SYS_COVERS = "/usr/share/themecfg/covers"          # read-only (shipped)

# lone '&' not part of an entity -> ES's parser tolerates it, ElementTree does not
_BAD_AMP = re.compile(r"&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);)")


def _parse(path):
    """Parse a gamelist that may contain unescaped '&' (ES is lenient)."""
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    root = ET.fromstring(_BAD_AMP.sub("&amp;", raw))
    return ET.ElementTree(root), root


def _stem(path):
    return os.path.splitext(os.path.basename(path))[0]


def _cover_path(stem):
    """Existing cover for a tool: user (regenerated) dir first, then shipped."""
    for d in (USER_COVERS, SYS_COVERS):
        p = os.path.join(d, stem + ".png")
        if os.path.exists(p):
            return p
    return None


def _icon_for(g):
    """The original square icon for a game (kept in <marquee> once repointed)."""
    src = g.findtext("marquee") or g.findtext("image") or ""
    if not src:
        return None
    return src if os.path.isabs(src) else os.path.join(MOD, src.lstrip("./"))


def apply_covers():
    """Re-point <image> to pre-baked cover PNGs. No ImageMagick."""
    if not os.path.isfile(GAMELIST):
        return 0
    tree, root = _parse(GAMELIST)
    made = 0
    for g in root.findall("game"):
        path = g.findtext("path") or ""
        img = g.findtext("image")
        if not path or not img:
            continue
        cov = _cover_path(_stem(path))
        if not cov or img == cov:
            continue
        # preserve the original icon once so --bake can find the source later
        if g.find("marquee") is None and not os.path.isabs(img):
            ET.SubElement(g, "marquee").text = img
        g.find("image").text = cov
        made += 1
    if made:
        tree.write(GAMELIST, encoding="UTF-8", xml_declaration=True)
    return made


def _bake_one(icon, out):
    # bg = the icon's most-frequent OPAQUE colour (robust to 1px borders /
    # rounded corners / antialiasing, unlike a single corner pixel).
    bg = "#1b212b"
    try:
        hist = subprocess.check_output(
            ["convert", icon, "-alpha", "on", "-depth", "8", "-format", "%c",
             "histogram:info:-"], stderr=subprocess.DEVNULL, timeout=30).decode()
        best_n = 0
        for line in hist.splitlines():
            m = re.search(r"(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6,8})", line)
            if not m:
                continue
            n, hx = int(m.group(1)), m.group(2)
            if len(hx) == 8 and hx[6:8].lower() == "00":   # transparent
                continue
            if n > best_n:
                best_n, bg = n, "#" + hx[:6]
    except Exception:  # noqa: BLE001
        pass

    try:
        wh = subprocess.check_output(
            ["convert", icon, "-format", "%wx%h", "info:"],
            stderr=subprocess.DEVNULL, timeout=30).decode().strip().split("x")
        w, h = int(wh[0]), int(wh[1])
    except Exception:  # noqa: BLE001
        w, h = 1000, 1000
    # pad to 2:3 (taller for square/wide icons; wider for very tall ones)
    if w * 3 >= h * 2:
        tw, th = w, (w * 3) // 2
    else:
        tw, th = (h * 2) // 3, h

    try:
        # -shave drops the icon's antialiased 1px edge so the padded bars meet a
        # clean bg (no faint seam). No resize -> the icon is never cropped.
        subprocess.run(
            ["convert", icon, "-shave", "3x3", "-background", bg,
             "-gravity", "center", "-extent", "%dx%d" % (tw, th), "-depth", "8", out],
            check=True, timeout=60, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write("bake failed for %s: %s\n" % (out, exc))
        return False


def bake_covers():
    """(Re)generate cover PNGs from the tool icons into USER_COVERS (ImageMagick)."""
    if not os.path.isfile(GAMELIST):
        return 0
    os.makedirs(USER_COVERS, exist_ok=True)
    _tree, root = _parse(GAMELIST)
    made = 0
    for g in root.findall("game"):
        path = g.findtext("path") or ""
        if not path:
            continue
        icon = _icon_for(g)
        if not icon or not os.path.exists(icon):
            continue
        if _bake_one(icon, os.path.join(USER_COVERS, _stem(path) + ".png")):
            made += 1
    return made


def bake_missing_covers():
    """Bake covers ONLY for tools that have none in either covers dir.

    This is what the boot quirk runs: a new upstream tool (its icon appears in
    the synced gamelist after an OTA, e.g. YAPS2 2026-07) would otherwise stay
    a square icon until the user manually rebuilds in the Theme Manager. The
    usual case is zero missing -> a pure XML scan, no ImageMagick at all.
    """
    if not os.path.isfile(GAMELIST):
        return 0
    _tree, root = _parse(GAMELIST)
    made = 0
    for g in root.findall("game"):
        path = g.findtext("path") or ""
        if not path or _cover_path(_stem(path)):
            continue
        icon = _icon_for(g)
        if not icon or not os.path.exists(icon):
            continue
        os.makedirs(USER_COVERS, exist_ok=True)
        if _bake_one(icon, os.path.join(USER_COVERS, _stem(path) + ".png")):
            made += 1
    return made


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--apply"
    if mode == "--bake":
        n = bake_covers()
        apply_covers()
        print("baked %d tool covers" % n)
    elif mode == "--bake-missing":
        n = bake_missing_covers()
        apply_covers()
        print("baked %d missing tool covers" % n)
    else:
        print("applied %d tool covers" % apply_covers())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
