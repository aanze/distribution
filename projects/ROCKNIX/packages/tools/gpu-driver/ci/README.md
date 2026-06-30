# Turnip driver catalogue (rocknix-turnip)

The on-device **GPU Driver Manager** (`/usr/bin/gpu-driver`, package
`packages/tools/gpu-driver`) lets you swap the Mesa Turnip (Vulkan) driver
per-game without rebuilding the OS. It fetches a catalogue of pre-built drivers
from a GitHub Release. This directory builds and publishes that catalogue.

## Why a separate repo + build-host script (not GitHub-hosted CI)

A `libvulkan_freedreno.so` must match the image's **exact ABI** (glibc, libdrm,
C++ runtime). The only robust way to guarantee that is to build it with the
**same ROCKNIX toolchain** that built the image. Your build host already has
that toolchain warm — one driver builds in ~2 min. A GitHub-hosted runner would
have to build the whole toolchain from scratch (hours) first, so we don't use
one. Run [`build-turnip-catalog.sh`](build-turnip-catalog.sh) on the build host,
or wire it to a **self-hosted** runner (your build host) via
[`workflow.yml`](workflow.yml).

> The popular Android Turnip builds (Mesa-Turnip-CI / KIMCHI / Winlator drivers)
> are built against **bionic** and will NOT load on ROCKNIX (glibc). That's the
> whole reason this exists.

## One-time setup

1. Create the release repo: `gh repo create aanze/rocknix-turnip --public`.
2. (Optional) install a self-hosted GitHub runner on the build host, label it
   `rocknix-build`, and copy `workflow.yml` into `rocknix-turnip/.github/workflows/`.

## Publishing a catalogue

From the ROCKNIX repo root, with the toolchain already built:

```sh
PROJECT=ROCKNIX DEVICE=SM8750 ARCH=aarch64 \
  ./projects/ROCKNIX/packages/tools/gpu-driver/ci/build-turnip-catalog.sh \
    --repo aanze/rocknix-turnip --tag catalog \
    stable:26.1.3 \
    stable:26.1.2 \
    git:origin/main:nightly
```

Version specs:

| spec | channel | example |
|------|---------|---------|
| `stable:<tag>` | stable | `stable:26.1.3` |
| `git:<ref>[:<label>]` | git | `git:origin/main:nightly` |
| `local:<path.so>` | perso | `local:/tmp/my-turnip.so` (a .so you built by hand, e.g. with a cherry-picked a830 MR) |

This builds each driver, packages the raw `.so` + a `manifest.json`, and (unless
`--no-publish`) uploads them all to the release.

### 1-click from Windows (recommended day-to-day)

A catalogue **source list** drives the whole thing, like `branches.txt` does for
builds. It and the wrappers live next to `build.sh` in
`~/scripts/rocknix-aanze/`:

- `catalog-sources.txt` — one spec per line (`stable:`/`git:`/`local:`), `#` to skip.
- `publish-turnip-catalog.sh [spec…] [--flags]` — appends any `spec` args to the
  list (deduped), then rebuilds + publishes the **whole** catalogue from it.
- `turnip-catalog.bat` (on the Windows Desktop) — runs that through WSL.

So the day-to-day flow is:

- **Add a driver**: `turnip-catalog.bat stable:26.2.0` (or `git:origin/main:nightly`)
  → adds it to `catalog-sources.txt` and rebuilds + publishes everything.
- **Rebuild current catalogue**: just double-click `turnip-catalog.bat`.
- **Dry run**: `turnip-catalog.bat git:origin/main:nightly --no-publish`.

Edit the list directly at
`\\wsl$\Ubuntu\home\marc\scripts\rocknix-aanze\catalog-sources.txt`.

## Coupling with the device CLI

`gpu-driver` defaults to:

```
GPU_DRIVER_MANIFEST_URL=https://github.com/aanze/rocknix-turnip/releases/latest/download/manifest.json
```

(see `MANIFEST_URL` in `../sources/bin/gpu-driver`). If you publish under a tag
other than the repo's "latest" release, either mark that release as *latest* on
GitHub, or change the constant / export `GPU_DRIVER_MANIFEST_URL`. The asset
URLs inside the manifest are built to match `--tag`, so keep them consistent.

The CLI verifies the SHA-256 from the manifest and **dlopen-probes** every
driver before installing it, so a corrupt or ABI-mismatched download is rejected
rather than installed.

## Offline behaviour & optional baked-in driver

The **stock** `/usr` driver is always present and is the guaranteed offline
fallback, so the device is fully functional with no network. On boot the
`094-gpu-driver` quirk opportunistically refreshes the catalogue (no-op
offline), so the GPU Driver Manager UI is pre-populated when online — it never
installs or switches anything on its own.

If you want a *second* driver available **fully offline** (baked into the
image), add a tiny package once a catalogue release exists:

```sh
# packages/tools/gpu-driver-bundle/package.mk (sketch)
PKG_NAME="gpu-driver-bundle"; PKG_TOOLCHAIN="manual"
PKG_URL="https://github.com/aanze/rocknix-turnip/releases/download/catalog/libvulkan_freedreno-turnip-26.1.3-stable.so"
PKG_SHA256="<sha from manifest.json>"
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/gpu-driver/bundled/turnip-26.1.3-stable
  cp -f ${PKG_BUILD}/* ${INSTALL}/usr/share/gpu-driver/bundled/turnip-26.1.3-stable/libvulkan_freedreno.so
}
```

then add `gpu-driver-bundle` to the `gpu-driver` case block in
`packages/misc/modules/package.mk`, and a first-boot line
`gpu-driver install-local /usr/share/gpu-driver/bundled/.../libvulkan_freedreno.so --id turnip-26.1.3-stable --mesa 26.1.3 --channel stable`.
We don't ship this by default to avoid committing/staling a ~15 MB blob and
because it requires the catalogue release to exist first.
