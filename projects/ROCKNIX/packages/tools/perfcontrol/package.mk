# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="perfcontrol"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE=""
PKG_URL=""
# gamepadcalibration provides the prebuilt aarch64 Pyxel venv we reuse at runtime.
PKG_DEPENDS_TARGET="toolchain Python3 gamepadcalibration"
PKG_LONGDESC="Perf Control: CPU/GPU underclock + fan-curve tool (Tools menu) with two-way profile sync to the Steam/Decky rocknix-control plugin."
PKG_TOOLCHAIN="manual"

# Supported devices = the Qualcomm handhelds that already bundle the Pyxel venv
# (gamepadcalibration) and have cpufreq/devfreq + the fancontrol service.
PERFCONTROL_DEVICES="SM8250 SM8550 SM8750"

make_target() {
  :
}

makeinstall_target() {
  # shared python core + headless CLI backend (run on the system python3)
  mkdir -p ${INSTALL}/usr/share/perfcontrol/app
  cp -f ${PKG_DIR}/sources/app/*.py ${INSTALL}/usr/share/perfcontrol/app/
  chmod 0644 ${INSTALL}/usr/share/perfcontrol/app/*.py

  mkdir -p ${INSTALL}/usr/bin
  cp -f ${PKG_DIR}/sources/bin/perfcontrol ${INSTALL}/usr/bin/perfcontrol
  chmod 0755 ${INSTALL}/usr/bin/perfcontrol

  # Tools-menu launcher (GUI)
  mkdir -p ${INSTALL}/usr/config/modules
  cp -f "${PKG_DIR}/sources/scripts/Perf Control.sh" ${INSTALL}/usr/config/modules/
  chmod 0755 ${INSTALL}/usr/config/modules/*.sh

  # boot re-apply quirk (clocks only) for the active device
  for d in ${PERFCONTROL_DEVICES}; do
    if [ "${DEVICE}" = "${d}" ]; then
      mkdir -p ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}
      cp -f ${PKG_DIR}/sources/quirks/095-perfcontrol \
        ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/095-perfcontrol
      chmod 0755 ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/095-perfcontrol
    fi
  done
}
