# gfn-electron (GeForce NOW client) — personal mod notes

Native-arm64 Electron GeForce NOW client (hmlendea/gfn-electron), bundled in the
image as a cleaner replacement-candidate for the buggy OpenNOW. Device-verified on
the AYN Odin 3 (SM8750): logged in + played a game.

## Why not the alternatives
- **NVIDIA official x86 GFN app + box64**: dead end. Decodes via Vulkan Video, which
  Adreno 830 / Turnip lacks (device decodes via qcom-iris V4L2). box64 can't bridge it.
- **gfn-electron upstream AppImage**: x86_64 only. We cross-build arm64 ourselves.

## Build recipe (arm64 bundle)
Pure-JS Electron app, no native deps → clean cross-build on the x86 WSL host:
```
git clone https://github.com/hmlendea/gfn-electron && cd gfn-electron
npm install
npx electron-builder --linux AppImage --arm64 --publish never
tar czf gfn-electron-<ver>-arm64.tar.gz --transform 's,^linux-arm64-unpacked,gfn-electron-<ver>,' -C dist linux-arm64-unpacked
```
The tarball (the `linux-arm64-unpacked/` tree, NOT the AppImage — can't extract an
arm64 AppImage on an x86 host) is cached in `sources/gfn-electron/` with `.sha256`+`.url`
so the ROCKNIX build is offline. `package.mk` installs it to `/usr/share/gfn-electron/`.

## Update method (decided)
Build-time bundle, NOT on-device download (upstream has no arm64 asset to pull, and a
web-wrapper rarely needs client updates). To update: bump PKG_VERSION + restage the
tarball + bump the hosted release, then a normal ROCKNIX rebuild refreshes it.

## Runtime integration (all in start_gfn-electron.sh, mirrors start_opennow.sh)
- Launch FROM EmulationStation only (else ES oledsaver wedges + half-screen tiling).
- Exit combo L1+START+SELECT: `set_kill set "geforcenow-electron wvkbd-mobintl"` —
  busybox killall needs the FULL exe name, not the 15-char comm `geforcenow-elec`.
- Keyboard: wvkbd `--hidden -L 380 -fn "Sans 22"`; summon = left-Home + tap screen.
- Suspend: AppRun wrapped in `systemd-inhibit --what=sleep:idle:...`.
- `for_window [app_id="GeForce NOW"] fullscreen enable` keeps OAuth popups fullscreen.

## OPEN DECISIONS (need Anze)
1. Replace OpenNOW or ship alongside? Currently shipped ALONGSIDE (non-destructive;
   both sections appear). Flip to replace = drop the opennow wiring.
2. Google login: blocked inside Electron ("browser may not be secure"). Currently
   documented as "use NVIDIA/Discord". Alternative = port OpenNOW's external-Firefox
   OAuth + localhost-redirect (more work).
3. Hosting the arm64 tarball (PKG_URL placeholder = github.com/Aanze/distribution
   release). Local build works from the sources/ cache regardless.
4. HW-decode confirmation still pending (needs a live stream): check /dev/video0
   (qcom-iris) busy + low CPU during play.
5. Art is placeholder (copied from OpenNOW). Real GeForce NOW art = polish.
