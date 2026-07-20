# kodi-app — Plex client (Kodi 21 + PM4K) for ROCKNIX

## What this is

Plex on the Odin 3 (and other SM8xxx devices) as an **opt-in ES section**:

- Backend: **Kodi 21.2 "Omega"** built from the `mediacenter/kodi` overlay
  (wayland/GLES client under sway, PipeWire audio, system ffmpeg 6.0.1).
  Kodi is NOT a mediacenter session — ES launches `kodi.bin` like a game.
- Client UI: **PM4K** (`script.plexmod`, pannal/plex-for-kodi) — the Plex
  client Plex staff themselves recommend on ARM64 Linux. 10-foot UI, gamepad
  navigation (via `peripheral.joystick`), login by plex.tv/link PIN code.
- Why not the Plex web app in Electron: Chromium has **no software HEVC
  decoder** (patents) and its hardware HEVC path needs VA-API, which
  Adreno/iris does not have. HEVC direct play was a hard requirement; the
  ffmpeg-based Kodi player direct-plays HEVC 8/10-bit, HDR (tone-mapped),
  TrueHD/DTS, PGS/ASS — the server never transcodes.

## Opt-in mechanics

Nothing shows on a fresh flash. `Tools > Install Plex` runs
`kodi-app-setup install` which only creates `/storage/roms/kodi/`
(launcher + seed gamelist) — ES lists a system only when it has ≥1 game.
`Uninstall Plex` removes the section but keeps `/storage/.kodi` (login,
watch state). Boot hook `031-kodi-preinstall` re-creates the section only if
the `.installed` marker exists. On top of that, the stock ES
"systems displayed" checkbox (HiddenSystems) can hide the section natively.

## The addons tarball (`kodi-app-<ver>.tar.gz`)

Plain repack of **unmodified** addon zips from the official Kodi mirror.
Composition of 1.0.0 (sha256 `529750732ac2…`):

| addon | version | source |
|---|---|---|
| script.plexmod | 1.0.6 | mirrors.kodi.tv/addons/omega/script.plexmod/ |
| script.module.requests | 2.31.0 | (required by plexmod) |
| script.module.six | 1.16.0+matrix.1 | (required by plexmod) |
| script.module.kodi-six | 0.1.3.1 | (required by plexmod) |
| script.module.urllib3 | 2.2.3 | (required by requests) |
| script.module.certifi | 2023.5.7 | (required by requests) |
| script.module.idna | 3.10.0 | (required by requests) |
| script.module.chardet | 5.1.0 | (required by requests) |

Refresh procedure:
1. `curl -sL https://mirrors.kodi.tv/addons/omega/script.plexmod/` → pick the
   newest zip; read its `addon.xml` `<requires>` and re-resolve the module
   closure (requests' own deps come from ITS addon.xml).
2. Unzip everything into `kodi-app-<newver>/`, tar.gz it, drop it in
   `sources/kodi-app/`, bump `PKG_VERSION` + `PKG_SHA256`, and upload the
   tarball to the `Aanze/distribution` release matching `PKG_URL`.
3. If the addon id set changed, update the manifest loop in
   `mediacenter/kodi/package.mk` (addon-manifest.xml auto-enable list).

No `repository.plexmod` bundled: script.plexmod is in the **official Kodi
repository**, so Kodi's stock repo updates it (system addons are shadowed by
newer versions installed under `/storage/.kodi/addons`).

## First-run seeds (`sources/seed/`, applied once by `kodi-app-setup ensure`)

- `guisettings.xml` — Kodi screensaver off + display power mgmt off (ES and
  the oledsaver own idle).
- `plexmod-settings.xml` — `kiosk.always=true`: Kodi boots straight into the
  PM4K UI, so ES > Plex lands directly in Plex.
- `kodi-gamepad.xml` — hold Back 2 s = clean Kodi quit → back to ES. Global
  L1+START+SELECT (`set_kill "kodi.bin"`) is the hard fallback.

## Build notes / gotchas

- Overlay packages added for the Kodi 21 toolchain: `mediacenter/kodi`,
  `mediacenter/kodi-platform`, `mediacenter/peripheral.joystick` (plain cmake
  pkg, NOT `PKG_IS_ADDON` — that machinery needs the unset `MEDIACENTER`),
  `mediacenter/JsonSchemaBuilder`, `mediacenter/TexturePacker` (literal
  `kodi` instead of `${MEDIACENTER}`), `devel/pcre` (Kodi 21 needs legacy
  PCRE; tree only has pcre2). `kodi-theme-Estuary` comes from the base tree
  unchanged (its deps are literal `kodi`).
- `libjpeg-turbo` overlay needed `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` on the
  HOST side too (toolchain cmake ≥ 4).
- All LE 12.0 kodi patches apply on 21.2 (offsets only). LE branding patches
  (RSS, LE repo, settings icon) dropped; LE systemd units / sleep.d NOT
  shipped (would interfere with the Odin 3 suspend path).
- HEVC hw decode via Kodi's DRMPRIME decoder = **tested live 2026-07-20 and
  BROKEN on iris**: `CDVDVideoCodecDRMPRIME` engages ffmpeg's
  `hevc_v4l2m2m` wrapper but the decoder loops on `send packet failed (EOF)`
  / `receive frame failed (EAGAIN)` -> audio only, frozen video. The PRIME
  toggles therefore STAY HIDDEN (upstream default, see the appliance.xml
  note). mpv's plain NV12 v4l2m2m probe DID decode, so the failure is in
  the drmprime/dmabuf output path - a future ffmpeg(v4l2-drmprime)/iris
  investigation could revive it. Software decode is the shipping baseline
  (~0.8 core for 1080p HEVC 10-bit; verified Direct Play, zero server
  transcode).
