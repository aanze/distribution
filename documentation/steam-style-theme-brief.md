# Design Brief — "Steam‑style" EmulationStation theme for ROCKNIX

> Hand this whole document to a designer / Claude Design. It is self‑contained.
> Goal: produce visual mockups **and** a buildable theme skeleton for the exact
> frontend ROCKNIX ships — not a generic "retro launcher."

---

## 1. What we're actually targeting (read this first)

The device runs **ROCKNIX** (a JELOS/LibreELEC‑lineage handheld Linux distro) on an
**AYN Odin 3** (Qualcomm SM8750), a **landscape ~1920×1080 / 16:9** handheld with
a full gamepad + touchscreen.

The frontend is **EmulationStation — specifically the `ROCKNIX/emulationstation-next`
fork, which is a descendant of *Batocera* EmulationStation.**

> ⚠️ This is **NOT** "ES‑DE" (EmulationStation Desktop Edition by Leon Styhre).
> Their theme formats are mutually incompatible. Do **not** use the ES‑DE theme
> engine, its `<view>` element set, its `gamelist`/`system` capabilities, or any
> ES‑DE documentation. A theme authored for ES‑DE will silently fail to load here.

Authoritative reference for the theme dialect we use:
- The Batocera EmulationStation theme engine (`formatVersion 7`).
- Our currently‑shipping theme: **Art Book Next** — `github.com/anthonycaccese/art-book-next-es`.
  Treat it as the gold‑standard example of what this engine can do.

Rendering reality:
- Pure **XML** theme description + asset files. **No HTML / CSS / JS / web engine
  exists in the image** — do not propose anything web‑based, no React, no DOM.
- Renderer is **OpenGL ES2 / GL via SDL2**, running under **Wayland** (gamescope‑style
  compositor session). Animations are limited to the engine's `<storyboard>` system.
- Assets allowed: **SVG, PNG, animated/GIF, video (mp4/webm)**, **TTF/OTF fonts**, WAV sounds.

---

## 2. The product goal

We want the **closest feel to Steam Big Picture / a gamescope console UI** that this
engine can express:

- A **top‑level "tab bar"** that lets the user move between **libraries / categories**:
  e.g. **PC (Windows/Steam/Heroic), PS3, Switch, … and a Tools menu**.
- A **grid of box/capsule art** for the games inside the selected tab, with a clean
  focus/selection state (glow / scale), like the Steam library grid.
- A **dark, high‑contrast, console‑grade** look. Controller‑first. Big touch targets.
- Persistent **status chrome**: clock, battery, network/Wi‑Fi, controller indicator —
  like the Steam status strip.
- A short **button‑hint bar** at the bottom (the engine calls this the *helpsystem*).

We are explicitly trying to *evoke* Steam, not pixel‑clone it. Use Steam's visual
grammar (dark slate palette, capsule art, focus glow, top nav, status strip) but
respect the engine's structural limits below.

---

## 3. How navigation REALLY works here (this constrains your layout)

EmulationStation has a **fixed two‑surface model**. You restyle these surfaces; you
cannot invent arbitrary screens or a free web‑style router.

1. **System view** — a single **`<carousel>`** of "systems." This is your raw material
   for the **top tab bar**. The carousel can be `horizontal`, `vertical`, or `wheel`;
   make it a horizontal strip of labels/logos across the top to read as Steam tabs.
   Each entry has a logo resolved by convention: `_inc/systems/logos/${system.theme}.svg`.

2. **Gamelist view** — the contents of the selected system. It has multiple skinnable
   variants you select per system: **`basic`**, **`detailed`** (adds metadata/video),
   and a **grid** (image‑grid / `gridtile`) variant. **The grid variant is your
   Steam‑capsule grid.** It supports a focused tile with scale/glow and an optional
   video/preview pane.

3. **menu** / **screen** views — system menu styling and global overlays.

### Mapping "tabs for PC / PS3 / Switch / Tools" onto this
There is **no native nested tab bar**. Two viable mappings (pick / combine):

- **A — Systems *are* the tabs (simplest, recommended for v1):** the horizontal
  system carousel = the tab bar. "PC", "PS3", "Switch", "Tools" are carousel entries.
  ROCKNIX already exposes these as systems (see §5). You style the carousel to look
  like Steam's top nav and the gamelist grid below as the capsule wall.

- **B — Collections as "libraries vs categories":** the engine supports **auto
  collections** ("All Games", "Favorites", "Last Played") and **custom collections**.
  Use these to create curated "library" tabs that span platforms (e.g. a single
  "PC" library merging Steam + Heroic + Windows). This gets closer to Steam's
  *library* concept but requires us to wire collections on the system side — flag it
  as a follow‑up and design for it, but don't assume it exists yet.

> Design the mockups so they work under **A** today, and note where **B** would
> upgrade the experience. Don't design a layout that *requires* something the engine
> can't do (free‑floating tab rows independent of the carousel, multi‑row tab nav, etc.).

---

## 4. Engine capabilities you can actually use

Elements available (confirmed in our shipping theme):
`carousel`, `image`, `video`, `text`, `textlist`, **image/grid tiles (`gridtile`)**,
`datetime`, `clock`, `rating`, `helpsystem` (button hints), `ninepatch` (scalable
frames/rounded panels), `sound`, `controllerActivity`, `batteryIndicator`,
`networkIcon`, `stackpanel`, `gameselector`, and **`storyboard`** animations
(opacity/scale/translate with easing: easeIn, Bump, linear, etc.).

Theming power features (use these — they're how we ship one theme that adapts):
- **`<subset>`** — user‑selectable theme variants (e.g. our theme offers selectable
  artwork styles, metadata on/off, logo animations). Use subsets to offer e.g.
  "Steam Dark" vs "Steam Light", grid vs list, animated vs static.
- **`<variables>`** + **`${...}`** substitution, including `${system.theme}`,
  `${screen.width/height/ratio}`, color vars.
- **Conditionals**: `if="..."` and `ifSubset="..."` on most elements.
- **Per‑aspect‑ratio includes** (`aspect-ratio-16-9.xml`, `-16-10`, `-4-3`, `-3-2`,
  `-1-1`, square). The Odin 3 is 16:9, but author the 16:9 file as primary and let
  the subset system fall back. (You do **not** need to solve every aspect ratio —
  prioritize 16:9.)
- **`colors.xml`** central palette, **`fonts.xml`** font registry, **`<include>`**
  for modular files, multi‑**`lang`** includes.

### Hard limits — do not design around these
- No web tech, no free‑form absolute‑positioned "any screen." You're skinning the
  system carousel + gamelist, not building a SPA.
- Navigation is single‑level (carousel → gamelist → launch). No true sub‑tabs without
  the collections trick (§3‑B).
- Animation = storyboards only. No physics, no shaders you author, no video shaders.
- Layout is normalized coordinates (0–1) + a fixed element vocabulary. Plan within it.

---

## 5. The content you're theming (so logos/art map correctly)

ROCKNIX exposes **~141 systems**. Logos are resolved by `system.theme` slug at
`_inc/systems/logos/<slug>.svg`. The Steam‑relevant / headline ones:

- **PC / launchers:** `steam`, `windows` (PC), `heroic` (Heroic/Epic/GOG),
  `moonlight` (game streaming), `opennow` (a ROCKNIX cloud/now‑gaming entry — we add
  a custom `opennow.svg` logo), `ports`.
- **Consoles called out by the requester:** `ps3` (PlayStation 3), `switch`
  (Nintendo Switch), plus the full retro set (`snes`, `genesis`, `psx`, `ps2`, `psp`,
  `n64`, `gc`, `wii`, `dreamcast`, `saturn`, `nds`, `3ds`, `gba`, `arcade`, `mame`, …).
- **`tools`** — special "system." Its games are shell scripts in
  `/storage/.config/modules` (`.sh`). This is the **Tools menu**; theme it as a
  utility tab, not a game grid (no box art — use icons/labels).

Full current slug list (provide a logo + selected/unselected state for at least the
headline ones; the rest can inherit a default):
```
3do 3ds amiga amigacd32 amstradcpc arcade arduboy atari2600 atari5200 atari7800
atari800 atarijaguar atarilynx atarist atomiswave bbcmicro bk c128 c16 c64 cdi
channelf chip-8 colecovision cps1 cps2 cps3 daphne doom dreamcast easyrpg famicom
fbneo fds gameandwatch gamegear gb gba gbc gbch gc genesis gp32 heroic intellivision
ios j2me macintosh mame mastersystem megacd megadrive megaduck model3 moonlight
moto mplayer msx msx2 n64 n64dd naomi nds ndsiware neogeo neogeocd nes ngp ngpc
odyssey2 openbor opennow palm pc pc88 pc98 pce-cd pcengine pcfx pet pico8 pokemini
ports ps2 ps3 psp psvita psx satellaview saturn scummvm scv sega32x segacd sfc
sg-1000 snes steam stv supergrafx supervision switch tg-cd tg16 tic80 tools triforce
uzebox vectrex vic20 videopac vircon32 virtualboy wasm4 wii wiiu wiiware windows
wonderswan wonderswancolor x1 x68000 xbox zmachine zx81 zxspectrum
```

---

## 6. Visual direction (Steam Big Picture / gamescope)

- **Palette:** Steam slate — deep blue‑gray backgrounds (`#1b2838`‑ish), darker
  panels (`#171a21`), bright accent for focus (Steam blue `#66c0f4` / `#1a9fff`),
  white/`#c7d5e0` text. Deliver this as a ready‑to‑drop **`colors.xml`** palette.
- **Top tab bar:** horizontal system carousel, large legible labels and/or system
  logos, clear focused vs unfocused (focused = bright + slight scale via storyboard).
- **Capsule grid:** rounded box art tiles (use `ninepatch` for rounded frames/shadows),
  Steam vertical‑capsule aspect (≈ 2:3) where art exists; focused tile gets a glow +
  scale bump + optional title/metadata reveal (detailed view).
- **Status strip:** top‑right `clock` + `batteryIndicator` + `networkIcon`
  (+ `controllerActivity`), Steam‑style.
- **Help bar:** bottom `helpsystem` with controller glyphs (A/B/X/Y, L/R, menu).
- **Motion:** subtle fades/slides on transitions (the carousel supports
  `fade & slide`); keep it snappy/console‑grade.
- **Typography:** a clean humanist sans (Steam uses Motiva Sans; pick a free
  equivalent like Inter / Fira Sans). Register in `fonts.xml`.

---

## 7. Deliverables

1. **Mockups** (16:9, 1920×1080) of: (a) system/tab view, (b) gamelist grid view
   focused on a capsule, (c) the Tools tab, (d) status strip + help bar detail.
2. A **theme folder skeleton** matching the Batocera ES `formatVersion 7` layout:
   ```
   theme.xml                  (root: includes, subsets, variables)
   colors.xml                 (Steam palette)
   fonts.xml
   aspect-ratio-16-9.xml      (primary layout; others optional/stubbed)
   _inc/
     systems/logos/<slug>.svg (headline systems first; default fallback)
     fonts/  images/  sounds/
   ```
3. **Asset conventions doc**: capsule art aspect + safe areas, logo
   sizing/padding rules, focus‑state spec, color tokens.
4. Notes on which Steam features need engine‑side work (the §3‑B collections path),
   so we can scope implementation.

Keep v1 achievable under **§3 mapping A** (systems = tabs). Mark anything that needs
collections or frontend changes as a clearly‑labeled "phase 2."

---

## 8. Addenda — how content gets wired (affects your grid design)

Two companion pieces are being built on the ROCKNIX side. They change two design
assumptions, so read this:

**(a) Cover art comes from SteamGridDB, standardized on vertical capsules.**
A fetcher will pull box art from SteamGridDB and write it into each game's **`image`**
metadata slot (with logo art going to `marquee`/`wheel` and "hero" art to `fanart`).
- **Design the capsule grid around the SteamGridDB vertical "grid" format: 600×900
  (2:3) PNG.** That is the Steam‑library capsule shape; make it the primary tile.
- Provide a graceful fallback tile for games with no cover yet (placeholder capsule
  using the system logo + title text).
- Where present, you may also use `fanart` (16:9 hero) as a blurred backdrop behind
  the focused tile, and `marquee`/`wheel` (transparent logo) as the title treatment —
  very close to Steam's focused‑game hero layout.

**(b) "Tabs" will be user‑chosen collections, not just raw systems.**
A Tools‑menu "Theme Manager" GUI will let the user pick which **collections** become
top‑level tabs (e.g. a single "PC" tab merging Steam + Heroic + Windows; a "Favorites"
tab; per‑platform tabs). Mechanically these are EmulationStation custom collections,
and each enabled one shows up as its own carousel entry — i.e. a tab. So:
- Design the **top carousel to gracefully handle a mix of**: real systems (PS3, Switch,
  Tools) **and** curated collection tabs (PC, Favorites, Recently Played) side by side.
- Each tab still needs a logo: collection tabs resolve their logo the same way
  (`_inc/systems/logos/<collection-theme>.svg`). Supply logos for the likely curated
  tabs: `pc`, `favorites`, `recent`/`lastplayed`, `allgames`, plus `custom-collections`.
- Keep tab labels/logos legible at small sizes since the count is user‑variable.
```
