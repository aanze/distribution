<img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/ducktale-logo.png?raw=yes" width=320>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[![Latest Version](https://img.shields.io/github/release/aanze/distribution.svg?color=1F4D2E&label=latest%20version&style=flat-square)](https://github.com/aanze/distribution/releases/latest) [![Activity](https://img.shields.io/github/commit-activity/m/aanze/distribution?color=1F4D2E&style=flat-square)](https://github.com/aanze/distribution/commits) [![Based on ROCKNIX](https://img.shields.io/badge/based%20on-ROCKNIX-1F4D2E?style=flat-square)](https://github.com/ROCKNIX/distribution)

---

**DUCKTALE** is a personal, customized fork of [ROCKNIX](https://github.com/ROCKNIX/distribution) for handheld gaming devices (primarily the AYN Odin 3 / SM8750). It tracks the official ROCKNIX nightlies and layers on a set of personal features — a Steam Big-Picture-style theme, on-device tooling, and quality-of-life fixes — while staying as close to upstream as possible.

Render unto Caesar: **all credit for the underlying OS goes to the ROCKNIX community.** DUCKTALE is not affiliated with or endorsed by the ROCKNIX project; it is simply a downstream build maintained for personal use. For the real thing, please use [ROCKNIX](https://github.com/ROCKNIX/distribution).

> The text below is from upstream ROCKNIX and describes the base distribution DUCKTALE is built on.

ROCKNIX is an immutable Linux distribution for handheld gaming devices developed by a small community of enthusiasts.  Our goal is to produce an operating system that has the features and capabilities that we need, and to have fun as we develop it.

## What DUCKTALE adds

On top of stock ROCKNIX:

* Steam Big-Picture-style **"steamlike"** theme: cover-art shelf, hero backdrops, console tabs.
* **Theme Manager** app: tune the look, set per-section backgrounds, pull cover/hero/logo art from SteamGridDB.
* **Boot into SteamOS**: boot straight to the Steam/gamescope session; "return to desktop" drops back to EmulationStation.
* **Perf Control**: CPU/GPU underclock and custom fan curves, two-way synced with the Steam plugin.
* **GPU Driver Manager**: swap the Mesa **Turnip** (Vulkan) driver **per game/emulator** (RPCS3, Citron, …) or globally — pick or download newer/experimental drivers from Perf Control or the Steam plugin, no OS rebuild. Drivers + build tools: [aanze/rocknix-turnip](https://github.com/aanze/rocknix-turnip). *(Adreno / Odin 3)*
* Built-in fork of the **Decky CPU/GPU/fan plugin** (installs with Decky, keeps your profile when you quit a game).
* One-tap **Decky Loader** install and **Proton-CachyOS** update/rollback. *(Steam-capable)*
* **GeForce NOW** as its own preinstalled main-menu section — a native-arm64 cloud-gaming client (log in with your NVIDIA account or Discord; no extra install step).
* On-demand **Nintendo Switch (Citron)** and **PS3 (RPCS3)** install/update tools.
* **Bypass charging**: run plugged in without charging or draining the battery. *(Odin 3)*
* **Two controller profiles — both with working back paddles**: emulate an **Xbox Elite** or a **DualSense Edge** pad; the Odin 3's back paddles act as real paddle buttons in games either way (kernel-level support, upstreamed to ROCKNIX). Switch from Quick Settings or the DUCKTALE-CONTROLS plugin. *(Odin 3)*
* **Right home button → Steam Quick Access**: open the Steam QAM with a single press. *(Odin 3)*
* **OLED anti-image-retention screensaver**: a sweeping pixel-shift overlay that keeps the screen from burning in. *(Odin 3)*
* **Screenshots & screen recording (video)**: capture a still, or one continuous clip — across EmulationStation, emulators, *and* Steam — saved to `roms/screenshots`. The two **back paddles** drive capture: *left home + left paddle* = record (toggle), *left home + right paddle* = screenshot (also *L1 + B* for a screenshot, *left home + Y* to record). *(Odin 3)*
* On-device **"update to my nightly"** from the Updates menu.

## Features

* ROCKNIX has a very active community of developers and users.
* Integrated cross-device local and remote network play.
* In-game touch support on supported devices.
* Fine grain control for battery life or performance.
* Includes support for playing Music and Video.
* Bluetooth audio and controller support.
* Support for HDMI audio and video out, and USB audio.
* Device to device and device to cloud sync with Syncthing and rclone.
* VPN support with Wireguard, Tailscale, and ZeroTier.
* Includes built-in support for scraping and retroachievements.

## Screenshots

Captured on an AYN Odin 3.

### The "steamlike" theme &amp; on-device tooling

More than a skin: a Steam Big-Picture-style EmulationStation front-end — console tabs, cover-art shelves and hero backdrops — fronting a whole on-device toolset. Several capabilities install as their own main-menu sections or Tools apps, set up straight from the handheld (no PC needed): update **Proton-CachyOS**, install/update **RPCS3** and **Citron**, and **GeForce NOW** as a native **arm64** cloud client — the official client built for ARM, not x86-emulated.

<table>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-tab-steam.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-tab-switch.png?raw=yes"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-tab-moonlight.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-tab-geforcenow.png?raw=yes"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-gamelist.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/theme-tools.png?raw=yes"/></td>
  </tr>
</table>

### Steam

Steam comes with its own built-in **DUCKTALE-CONTROLS** Decky plugin, so the whole system can be driven from the Quick Access menu without leaving the game: **underclock presets** (bound to the on-device Perf Control profiles), a **fan curve**, a **charge-bypass toggle**, and a **gamepad-profile switch**.

<table>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/steam-ducktale-controls.png?raw=yes"/></td>
  </tr>
</table>

### Perf Control

On-device CPU/GPU underclock and fan-curve tool (Tools section), two-way synced with the Steam plugin:

<table>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/perfcontrol-profiles.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/perfcontrol-cpu.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/perfcontrol-gpu.png?raw=yes"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/perfcontrol-fan.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/perfcontrol-monitor.png?raw=yes"/></td>
    <td></td>
  </tr>
</table>

### GPU Driver

Swap the Mesa **Turnip** (Vulkan) driver **without rebuilding the OS** — pick it globally or **per game/emulator** (great for RPCS3, Citron and other Vulkan-heavy cores) from the **DRIVER** tab in Perf Control, or from the Steam/Decky panel. Download newer or experimental drivers from an online catalogue and mark favourites; the desktop compositor always stays on the rock-solid stock driver, and a broken default auto-reverts on the next boot.

Drivers — and the tools that build them for ROCKNIX (glibc/ARM64, from Mesa releases, mesa-git, or community Turnip source) — live in a companion repo: **[aanze/rocknix-turnip](https://github.com/aanze/rocknix-turnip)**.

### Theme Manager

Separate Tools app to customise the steamlike theme — look, per-section backgrounds, and SteamGridDB cover/hero/logo art:

<table>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/thememanager-look.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/thememanager-art.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/thememanager-backgrounds.png?raw=yes"/></td>
  </tr>
  <tr>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/thememanager-steamgriddb.png?raw=yes"/></td>
    <td><img src="https://github.com/aanze/distribution/blob/aanze-next/distributions/ROCKNIX/logos/screenshots/thememanager-about.png?raw=yes"/></td>
    <td></td>
  </tr>
</table>

## Community

The ROCKNIX community utilizes Discord for discussion, if you would like to join us please use this link: [https://discord.gg/seTxckZjJy](https://discord.gg/seTxckZjJy)

## Licenses

**ROCKNIX** is a fork of [JELOS](https://github.com/JustEnoughLinuxOS/distribution/), all licenses apply and credit to the JELOS team. 

You are free to:

- Share: copy and redistribute the material in any medium or format
- Adapt: remix, transform, and build upon the material

Under the following terms:

- Attribution: You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- NonCommercial: You may not use the material for commercial purposes.
- ShareAlike: If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.

### ROCKNIX Software

Copyright (C) 2024-present [ROCKNIX](https://github.com/ROCKNIX)

Original software and scripts developed by the ROCKNIX are licensed under the terms of the [GNU GPL Version 2](https://choosealicense.com/licenses/gpl-2.0/).  The full license can be found in this project's licenses folder.

### Bundled Works
All other software is provided under each component's respective license.  These licenses can be found in the software sources or in this project's licenses folder.  Modifications to bundled software and scripts by the JELOS team are licensed under the terms of the software being modified.

## Credits

Like any Linux distribution, this project is not the work of one person.  It is the work of many persons all over the world who have developed the open source bits without which this project could not exist.  Special thanks to CoreELEC, LibreELEC, JELOS, and to developers and contributors across the open source community.
