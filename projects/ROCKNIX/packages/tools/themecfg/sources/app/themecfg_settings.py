# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Read/write the steamlike theme's live customisations. The theme <include>s
# /storage/.config/themecfg/custom.xml AFTER its defaults, so the <variables>
# we write here override the look. Pure stdlib (shared by the Pyxel GUI).

import os
import re

CONFIG_DIR = "/storage/.config/themecfg"
CUSTOM_XML = os.path.join(CONFIG_DIR, "custom.xml")
SCRIM_RGB = "0a0f14"          # base colour for the hero-darkness scrim

# Ordered customisation spec. The GUI renders this list generically.
#   cycle  : options = [(label, value), ...]
#   int    : min,max,step
#   float  : min,max,step,fmt
#   toggle : value is 'true'/'false'
#   alpha  : 0..100% -> SCRIM_RGB + AA (hero darkness)
SETTINGS = [
    {"key": "colAccent", "label": "Accent colour", "kind": "cycle", "options": [
        ("Steam Blue", "66c0f4ff"), ("Cyan", "2effdfff"), ("Green", "57ff7aff"),
        ("Orange", "ff8c2bff"), ("Purple", "b18cffff"), ("Red", "ff5a5aff"),
        ("Gold", "f4c066ff"), ("White", "ffffffff")]},
    {"key": "colScrim", "label": "Hero darkness", "kind": "alpha", "min": 20, "max": 95},
    {"key": "shelfCols", "label": "Shelf columns", "kind": "int", "min": 6, "max": 10, "step": 1},
    {"key": "shelfZoom", "label": "Selected zoom", "kind": "float",
     "min": 1.0, "max": 1.30, "step": 0.02, "fmt": "%.2f"},
    {"key": "selFrame", "label": "Selection frame", "kind": "cycle", "options": [
        ("White", "ffffffff"), ("Subtle", "ffffff66"), ("Accent-Blue", "66c0f4ff"),
        ("Green", "57ff7aff"), ("None", "00000000")]},
    {"key": "showLogos", "label": "Platform logos", "kind": "toggle"},
    {"key": "showVideo", "label": "Video previews", "kind": "toggle"},
    {"key": "showClock", "label": "Show clock", "kind": "toggle"},
    {"key": "showTags", "label": "Game tags (year/genre)", "kind": "toggle"},
]

DEFAULTS = {
    "colAccent": "66c0f4ff", "colScrim": "0a0f1499", "shelfCols": "8",
    "shelfZoom": "1.08", "selFrame": "ffffffff",
    "showLogos": "1", "showVideo": "1", "showClock": "1", "showTags": "1",
}


def load():
    vals = dict(DEFAULTS)
    try:
        with open(CUSTOM_XML, encoding="utf-8") as fh:
            txt = fh.read()
        for k in DEFAULTS:
            m = re.search(r"<%s>(.*?)</%s>" % (k, k), txt)
            if m:
                vals[k] = m.group(1).strip()
    except OSError:
        pass
    return vals


def save(vals):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    out = ['<?xml version="1.0" encoding="UTF-8"?>', "<theme>", "   <variables>"]
    for k in DEFAULTS:
        out.append("      <%s>%s</%s>" % (k, vals.get(k, DEFAULTS[k]), k))
    out += ["   </variables>", "</theme>", ""]
    tmp = CUSTOM_XML + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    os.replace(tmp, CUSTOM_XML)


# ---- alpha (hero darkness) helpers --------------------------------------- #
def alpha_pct(value):
    try:
        return round(int(value[6:8], 16) / 255.0 * 100)
    except (ValueError, IndexError):
        return 60


def alpha_set(pct):
    a = max(0, min(255, round(pct / 100.0 * 255)))
    return SCRIM_RGB + "%02x" % a


# ---- generic value display + adjust for the GUI -------------------------- #
def display(setting, value):
    k = setting["kind"]
    if k == "cycle":
        for lbl, val in setting["options"]:
            if val == value:
                return lbl
        return value
    if k == "toggle":
        return "ON" if value == "1" else "OFF"
    if k == "alpha":
        return "%d%%" % alpha_pct(value)
    if k == "int":
        return str(value)
    if k == "float":
        try:
            return setting.get("fmt", "%s") % float(value)
        except ValueError:
            return value
    return value


def adjust(setting, value, direction):
    """Return the new value after a left(-1)/right(+1) press."""
    k = setting["kind"]
    if k == "cycle":
        vals = [v for _, v in setting["options"]]
        i = vals.index(value) if value in vals else 0
        return vals[(i + direction) % len(vals)]
    if k == "toggle":
        return "0" if value == "1" else "1"
    if k == "alpha":
        return alpha_set(max(setting["min"], min(setting["max"],
                                                  alpha_pct(value) + direction * 5)))
    if k == "int":
        n = int(float(value)) + direction * setting["step"]
        return str(max(setting["min"], min(setting["max"], n)))
    if k == "float":
        n = round(float(value) + direction * setting["step"], 2)
        n = max(setting["min"], min(setting["max"], n))
        return ("%.2f" % n)
    return value
