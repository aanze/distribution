# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)
#
# ROCKNIX overlay port of LE 12.0's pcre (legacy PCRE 8.x). Kodi 21 "Omega"
# (the Plex/PM4K client backend, see mediacenter/kodi) requires legacy PCRE;
# the tree only carries pcre2. Static lib only, nothing enters the image.

PKG_NAME="pcre"
PKG_VERSION="8.45"
PKG_SHA256="4dae6fdcd2bb0bb6c37b5f97c33c2be954da743985369cddac3546e3218bffb8"
PKG_LICENSE="OSS"
PKG_SITE="http://www.pcre.org/"
PKG_URL="${SOURCEFORGE_SRC}/pcre/${PKG_NAME}/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A set of functions that implement regular expression pattern matching."
PKG_TOOLCHAIN="configure"
PKG_BUILD_FLAGS="+pic"

PKG_CONFIGURE_OPTS_TARGET="--disable-shared \
             --enable-static \
             --enable-utf8 \
             --disable-cpp \
             --enable-pcre16 \
             --enable-unicode-properties \
             --with-gnu-ld"

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin
  cp ${PKG_NAME}-config ${TOOLCHAIN}/bin
  sed -e "s:\(['= ]\)/usr:\\1${PKG_ORIG_SYSROOT_PREFIX}/usr:g" -i ${TOOLCHAIN}/bin/${PKG_NAME}-config
  chmod +x ${TOOLCHAIN}/bin/${PKG_NAME}-config
}
