# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="perfcontrol"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE=""
PKG_URL=""
# gamepadcalibration provides the prebuilt aarch64 Pyxel venv we reuse at runtime.
PKG_DEPENDS_TARGET="toolchain Python3 gamepadcalibration"
PKG_LONGDESC="Perf Control: CPU/GPU underclock + fan-curve tool (Main Menu > System Settings > Performance, and the Quick Access menu) with two-way profile sync to the Steam/Decky DUCKTALE-CONTROLS plugin."
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

  # GUI launcher, invoked from the ES menus (System Settings > Performance and
  # the Quick Access modal). NOT installed under /usr/config/modules, so it does
  # not show up as a Tools entry.
  mkdir -p ${INSTALL}/usr/share/perfcontrol
  cp -f "${PKG_DIR}/sources/scripts/perfcontrol-gui" ${INSTALL}/usr/share/perfcontrol/perfcontrol-gui
  chmod 0755 ${INSTALL}/usr/share/perfcontrol/perfcontrol-gui

  # boot + post-resume re-apply quirks (clocks only) for the active device.
  # The resume one matters: deep suspend offlines cpu6/7, which tears down the
  # big-cluster cpufreq policy and resets its max cap to factory at resume.
  for d in ${PERFCONTROL_DEVICES}; do
    if [ "${DEVICE}" = "${d}" ]; then
      mkdir -p ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}
      cp -f ${PKG_DIR}/sources/quirks/095-perfcontrol \
        ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/095-perfcontrol
      chmod 0755 ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/095-perfcontrol

      mkdir -p ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/sleep.d/post
      cp -f ${PKG_DIR}/sources/quirks/095-perfcontrol-resume \
        ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/sleep.d/post/095-perfcontrol
      chmod 0755 ${INSTALL}/usr/lib/autostart/quirks/platforms/${DEVICE}/sleep.d/post/095-perfcontrol
    fi
  done
}
