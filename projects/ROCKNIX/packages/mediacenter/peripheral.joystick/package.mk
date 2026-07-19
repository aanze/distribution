# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Lukas Rusak (lrusak@libreelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)
#
# ROCKNIX overlay package (LE 12.0 pin, from kodi-binary-addons/). Gamepad
# support for the Kodi-based Plex client (PM4K): without this binary addon
# Kodi ignores joysticks entirely.
#
# Unlike LE this is a plain cmake package, NOT PKG_IS_ADDON="embedded": the
# LE addon machinery requires the global MEDIACENTER variable, which ROCKNIX
# leaves unset. The addon's own CMakeLists (via the kodi:host KodiConfig)
# installs straight into /usr/lib/kodi/addons + /usr/share/kodi/addons, i.e.
# baked into the image; the kodi package's addon-manifest.xml auto-enables it
# at first run.

PKG_NAME="peripheral.joystick"
PKG_VERSION="21.1.23-Omega"
PKG_SHA256="7392c30a9e49b0cd219cdca14f5b20ffce9f4a52c349c2cdf37cb603dd21f516"
PKG_REV="1"
PKG_ARCH="any"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/xbmc/peripheral.joystick"
PKG_URL="https://github.com/xbmc/peripheral.joystick/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain kodi-platform p8-platform systemd"
PKG_SECTION=""
PKG_SHORTDESC="peripheral.joystick: Joystick support in Kodi"
PKG_LONGDESC="peripheral.joystick provides joystick support and button mapping"
PKG_BUILD_FLAGS="+lto"

# toolchain cmake >= 4 refuses the addon's older cmake_minimum_required
PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
