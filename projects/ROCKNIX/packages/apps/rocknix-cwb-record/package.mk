# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX/DUCKTALE

PKG_NAME="rocknix-cwb-record"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="System-wide screen recorder: DPU CWB NV12 capture -> Iris H.264 (V4L2 M2M)"
PKG_TOOLCHAIN="manual"

make_target() {
  ${CC} ${CFLAGS} ${LDFLAGS} -O2 -o rocknix-cwb-record \
    ${PKG_DIR}/sources/rocknix-cwb-record.c
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp rocknix-cwb-record ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/rocknix-cwb-record
}
