# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gpu-driver"
PKG_VERSION="0.1"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain Python3 vulkan-tools"
PKG_LONGDESC="GPU Driver Manager: install/select swappable Mesa Turnip (Vulkan) drivers per-game without rebuilding the OS. CLI backend used by runemu/Steam env injection and the DUCKTALE-CONTROLS Decky plugin."
PKG_TOOLCHAIN="manual"

# Freedreno/Turnip (Vulkan) handhelds only. The whole mechanism is Vulkan-ICD
# swapping (VK_DRIVER_FILES), so it only makes sense where the GPU driver is
# Mesa freedreno. Gate to the Qualcomm Adreno devices.
GPU_DRIVER_DEVICES="SM8250 SM8550 SM8650 SM8750"

make_target() {
  :
}

makeinstall_target() {
  for d in ${GPU_DRIVER_DEVICES}; do
    if [ "${DEVICE}" = "${d}" ]; then
      # headless CLI backend (system python3, stdlib only)
      mkdir -p ${INSTALL}/usr/bin
      cp -f ${PKG_DIR}/sources/bin/gpu-driver ${INSTALL}/usr/bin/gpu-driver
      chmod 0755 ${INSTALL}/usr/bin/gpu-driver

      # boot guard: validate the active default driver, auto-revert to stock if broken
      mkdir -p ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}
      cp -f ${PKG_DIR}/sources/quirks/094-gpu-driver \
        ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/094-gpu-driver
      chmod 0755 ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/094-gpu-driver
    fi
  done
}
