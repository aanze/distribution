# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2017-present Team LibreELEC (https://libreelec.tv)
#
# ROCKNIX overlay copy (shadows the base packages/mediacenter/kodi, which pins
# a Kodi 22 ALPHA that needs ffmpeg 7.x). This copy is LibreELEC 12.0's Kodi
# 21.2 "Omega" package, the distro-proven pairing with the project ffmpeg 6.0.1
# overlay, and the primary target of PM4K (script.plexmod, the Plex client).
# Kodi is NOT a mediacenter session here: EmulationStation owns the session and
# launches kodi.bin fullscreen under sway as the "Plex" ES system (see the
# plex-kodi package). Consequently, compared to LE:
#  - no systemd units / sleep.d / tmpfiles.d / profile.d are shipped (ES owns
#    the lifecycle; LE's sleep hooks would interfere with the Odin 3 suspend)
#  - no LibreELEC repository addon; instead the addon-manifest auto-enables
#    peripheral.joystick (gamepad) and the bundled PM4K addons (plex-kodi pkg)
#  - audio is PipeWire (native AESink), video HEVC decode is ffmpeg software
#    (DRMPRIME/v4l2 hw decode = parked stretch goal)

PKG_NAME="kodi"
PKG_VERSION="21.2-Omega"
PKG_SHA256="da3a5df663684664b9383b65f1c06568222629d935084a59e4e641fcdcb6c383"
PKG_LICENSE="GPL"
PKG_SITE="http://www.kodi.tv"
PKG_URL="https://github.com/xbmc/xbmc/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain JsonSchemaBuilder:host TexturePacker:host Python3 zlib systemd lzo pcre swig:host libass curl fontconfig fribidi tinyxml tinyxml2 libjpeg-turbo freetype libcdio taglib libxml2 libxslt rapidjson sqlite ffmpeg crossguid libdvdnav libfmt lirc libfstrcmp flatbuffers:host flatbuffers libudfread spdlog"
PKG_DEPENDS_UNPACK="commons-lang3 commons-text groovy"
PKG_DEPENDS_HOST="toolchain"
PKG_LONGDESC="A free and open source cross-platform media player."
PKG_BUILD_FLAGS="+speed"

configure_package() {
  # ROCKNIX: PipeWire is the system audio server; Kodi 21 has a native AESink
  # for it (mutually exclusive with the ALSA/Pulse sinks below).
  KODI_PIPEWIRE_SUPPORT="yes"

  # Single threaded LTO is very slow so rely on Kodi for parallel LTO support
  if [ "${LTO_SUPPORT}" = "yes" ] && ! build_with_debug; then
    PKG_KODI_USE_LTO="-DUSE_LTO=${CONCURRENCY_MAKE_LEVEL}"
  fi

  # Set linker options
  case $(get_target_linker) in
    gold)
      PKG_KODI_LINKER="-DENABLE_GOLD=ON \
                       -DENABLE_MOLD=OFF"
      ;;
    mold)
      PKG_KODI_LINKER="-DENABLE_GOLD=OFF \
                       -DENABLE_MOLD=ON \
                       -DMOLD_EXECUTABLE=${TOOLCHAIN}/${TARGET_NAME}/bin/mold"
      ;;
    *)
      PKG_KODI_LINKER="-DENABLE_GOLD=OFF \
                       -DENABLE_MOLD=OFF"
      ;;
  esac

  get_graphicdrivers

  if [ "${TARGET_ARCH}" = "x86_64" ]; then
    PKG_DEPENDS_TARGET+=" pciutils"
  fi

  PKG_DEPENDS_TARGET+=" dbus"

  if [ "${DISPLAYSERVER}" = "x11" ]; then
    PKG_DEPENDS_TARGET+=" libX11 libXext libdrm libXrandr"
    KODI_PLATFORM="-DCORE_PLATFORM_NAME=x11 \
                   -DAPP_RENDER_SYSTEM=gl"
  elif [ "${DISPLAYSERVER}" = "wl" ]; then
    PKG_DEPENDS_TARGET+=" wayland waylandpp"
    PKG_PATCH_DIRS+=" wayland"
    CFLAGS+=" -DEGL_NO_X11"
    CXXFLAGS+=" -DEGL_NO_X11"
    KODI_PLATFORM="-DCORE_PLATFORM_NAME=wayland \
                   -DAPP_RENDER_SYSTEM=gles \
                   -DWAYLANDPP_SCANNER=${TOOLCHAIN}/bin/wayland-scanner++ \
                   -DWAYLANDPP_PROTOCOLS_DIR=${SYSROOT_PREFIX}/usr/share/waylandpp/protocols \
                   -DWAYLAND_PROTOCOLS_DIR=${SYSROOT_PREFIX}/usr/share/wayland-protocols"
  fi

  if [ ! "${OPENGL}" = "no" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGL} glu"
  fi

  if [ "${OPENGLES_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  fi

  if [ "${KODI_ALSA_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" alsa-lib"
    KODI_ALSA="-DENABLE_ALSA=ON"
  else
    KODI_ALSA="-DENABLE_ALSA=OFF"
  fi

  if [ "${KODI_PULSEAUDIO_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" pulseaudio"
    KODI_PULSEAUDIO="-DENABLE_PULSEAUDIO=ON"
  else
    KODI_PULSEAUDIO="-DENABLE_PULSEAUDIO=OFF"
  fi

  if [ "${ESPEAK_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" espeak-ng"
  fi

  if [ "${KODI_PIPEWIRE_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" pipewire"
    KODI_PIPEWIRE="-DENABLE_PIPEWIRE=ON"

    if [ "${KODI_PULSEAUDIO_SUPPORT}" = "yes" -o "${KODI_ALSA_SUPPORT}" = "yes" ]; then
      die "KODI_PULSEAUDIO_SUPPORT and KODI_ALSA_SUPPORT cannot be used with KODI_PIPEWIRE_SUPPORT"
    fi
  else
    KODI_PIPEWIRE="-DENABLE_PIPEWIRE=OFF"
  fi

  if [ "${CEC_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libcec"
    KODI_CEC="-DENABLE_CEC=ON"
  else
    KODI_CEC="-DENABLE_CEC=OFF"
  fi

  if [ "${CEC_FRAMEWORK_SUPPORT}" = "yes" ]; then
    PKG_PATCH_DIRS+=" cec-framework"
  fi

  if [ "${KODI_OPTICAL_SUPPORT}" = yes ]; then
    KODI_OPTICAL="-DENABLE_OPTICAL=ON"
  else
    KODI_OPTICAL="-DENABLE_OPTICAL=OFF"
  fi

  if [ "${KODI_DVDCSS_SUPPORT}" = yes ]; then
    KODI_DVDCSS="-DENABLE_DVDCSS=ON \
                 -DLIBDVDCSS_URL=${SOURCES}/libdvdcss/libdvdcss-$(get_pkg_version libdvdcss).tar.gz"
  else
    KODI_DVDCSS="-DENABLE_DVDCSS=OFF"
  fi

  if [ "${KODI_BLURAY_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libbluray"
    KODI_BLURAY="-DENABLE_BLURAY=ON"
  else
    KODI_BLURAY="-DENABLE_BLURAY=OFF"
  fi

  if [ "${AVAHI_DAEMON}" = yes ]; then
    PKG_DEPENDS_TARGET+=" avahi nss-mdns"
    KODI_AVAHI="-DENABLE_AVAHI=ON"
  else
    KODI_AVAHI="-DENABLE_AVAHI=OFF"
  fi

  case "${KODI_MYSQL_SUPPORT}" in
    mysql)   PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} mysql"
             KODI_MYSQL="-DENABLE_MYSQLCLIENT=ON -DENABLE_MARIADBCLIENT=OFF"
             ;;
    mariadb) PKG_DEPENDS_TARGET="${PKG_DEPENDS_TARGET} mariadb-connector-c"
             KODI_MYSQL="-DENABLE_MARIADBCLIENT=ON -DENABLE_MYSQLCLIENT=OFF"
             ;;
    *)       KODI_MYSQL="-DENABLE_MYSQLCLIENT=OFF -DENABLE_MARIADBCLIENT=OFF"
  esac

  if [ "${KODI_AIRPLAY_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libplist"
    KODI_AIRPLAY="-DENABLE_PLIST=ON"
  else
    KODI_AIRPLAY="-DENABLE_PLIST=OFF"
  fi

  if [ "${KODI_AIRTUNES_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libshairplay"
    KODI_AIRTUNES="-DENABLE_AIRTUNES=ON"
  else
    KODI_AIRTUNES="-DENABLE_AIRTUNES=OFF"
  fi

  if [ "${KODI_NFS_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libnfs"
    KODI_NFS="-DENABLE_NFS=ON"
  else
    KODI_NFS="-DENABLE_NFS=OFF"
  fi

  if [ "${KODI_SAMBA_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" samba"
    KODI_SAMBA="-DENABLE_SMBCLIENT=ON"
  else
    KODI_SAMBA="-DENABLE_SMBCLIENT=OFF"
  fi

  if [ "${KODI_WEBSERVER_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libmicrohttpd"
  fi

  if [ "${KODI_UPNP_SUPPORT}" = yes ]; then
    KODI_UPNP="-DENABLE_UPNP=ON"
  else
    KODI_UPNP="-DENABLE_UPNP=OFF"
  fi

  if [ "${TARGET_ARCH}" = "aarch64" -o "${TARGET_ARCH}" = "arm" ]; then
    if target_has_feature neon; then
      KODI_NEON="-DENABLE_NEON=ON"
    else
      KODI_NEON="-DENABLE_NEON=OFF"
    fi
  else
    KODI_NEON=""
  fi

  if [ "${VDPAU_SUPPORT}" = "yes" -a "${DISPLAYSERVER}" = "x11" ]; then
    PKG_DEPENDS_TARGET+=" libvdpau"
    KODI_VDPAU="-DENABLE_VDPAU=ON"
  else
    KODI_VDPAU="-DENABLE_VDPAU=OFF"
  fi

  if [ "${VAAPI_SUPPORT}" = yes ]; then
    PKG_DEPENDS_TARGET+=" libva"
    KODI_VAAPI="-DENABLE_VAAPI=ON"
  else
    KODI_VAAPI="-DENABLE_VAAPI=OFF"
  fi

  if [ "${TARGET_ARCH}" = "x86_64" ]; then
    KODI_ARCH="-DWITH_CPU=${TARGET_ARCH}"
  else
    KODI_ARCH="-DWITH_ARCH=${TARGET_ARCH}"
  fi

  if [ ! "${KODIPLAYER_DRIVER}" = "default" -a "${DISPLAYSERVER}" = "no" ]; then
    PKG_DEPENDS_TARGET+=" ${KODIPLAYER_DRIVER} libinput libxkbcommon libdisplay-info"
    if [ "${OPENGLES_SUPPORT}" = yes -a "${KODIPLAYER_DRIVER}" = "${OPENGLES}" ]; then
      KODI_PLATFORM="-DCORE_PLATFORM_NAME=gbm -DAPP_RENDER_SYSTEM=gles"
      CFLAGS+=" -DEGL_NO_X11"
      CXXFLAGS+=" -DEGL_NO_X11"
      PKG_APPLIANCE_XML="${PKG_DIR}/config/appliance-gbm.xml"
    fi
  fi

  KODI_LIBDVD="${KODI_DVDCSS} \
               -DLIBDVDNAV_URL=${SOURCES}/libdvdnav/libdvdnav-$(get_pkg_version libdvdnav).tar.gz \
               -DLIBDVDREAD_URL=${SOURCES}/libdvdread/libdvdread-$(get_pkg_version libdvdread).tar.gz"

  PKG_CMAKE_OPTS_TARGET="-DNATIVEPREFIX=${TOOLCHAIN} \
                         -DWITH_TEXTUREPACKER=${TOOLCHAIN}/bin/TexturePacker \
                         -DWITH_JSONSCHEMABUILDER=${TOOLCHAIN}/bin/JsonSchemaBuilder \
                         -DSWIG_EXECUTABLE=${TOOLCHAIN}/bin/swig \
                         -DPYTHON_EXECUTABLE=${TOOLCHAIN}/bin/${PKG_PYTHON_VERSION} \
                         -DPYTHON_INCLUDE_DIRS=${SYSROOT_PREFIX}/usr/include/${PKG_PYTHON_VERSION} \
                         -DGIT_VERSION=${PKG_VERSION} \
                         -DFFMPEG_PATH=${SYSROOT_PREFIX}/usr \
                         -DENABLE_INTERNAL_FFMPEG=OFF \
                         -DENABLE_INTERNAL_CROSSGUID=OFF \
                         -DENABLE_INTERNAL_UDFREAD=OFF \
                         -DENABLE_INTERNAL_SPDLOG=OFF \
                         -DENABLE_INTERNAL_RapidJSON=OFF \
                         -DENABLE_UDEV=ON \
                         -DENABLE_DBUS=ON \
                         -DENABLE_XSLT=ON \
                         -DENABLE_CCACHE=OFF \
                         -DENABLE_LIRCCLIENT=ON \
                         -DENABLE_EVENTCLIENTS=ON \
                         -DENABLE_DEBUGFISSION=OFF \
                         -DENABLE_APP_AUTONAME=OFF \
                         -DENABLE_TESTING=OFF \
                         -DENABLE_INTERNAL_FLATBUFFERS=OFF \
                         -DENABLE_LCMS2=OFF \
                         -DENABLE_SNDIO=OFF \
                         -DADDONS_CONFIGURE_AT_STARTUP=OFF \
                         -Dgroovy_SOURCE_DIR=$(get_build_dir groovy) \
                         -Dapache-commons-lang_SOURCE_DIR=$(get_build_dir commons-lang3) \
                         -Dapache-commons-text_SOURCE_DIR=$(get_build_dir commons-text) \
                         ${PKG_KODI_USE_LTO} \
                         ${PKG_KODI_LINKER} \
                         ${KODI_ARCH} \
                         ${KODI_NEON} \
                         ${KODI_VDPAU} \
                         ${KODI_VAAPI} \
                         ${KODI_CEC} \
                         ${KODI_PLATFORM} \
                         ${KODI_SAMBA} \
                         ${KODI_NFS} \
                         ${KODI_LIBDVD} \
                         ${KODI_AVAHI} \
                         ${KODI_UPNP} \
                         ${KODI_MYSQL} \
                         ${KODI_AIRPLAY} \
                         ${KODI_AIRTUNES} \
                         ${KODI_OPTICAL} \
                         ${KODI_BLURAY} \
                         ${KODI_ALSA} \
                         ${KODI_PULSEAUDIO} \
                         ${KODI_PIPEWIRE}"
}

configure_host() {
  setup_toolchain target:cmake
  cmake ${CMAKE_GENERATOR_NINJA} \
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_CONF} \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
        -DHEADERS_ONLY=ON \
        ${KODI_ARCH} \
        ${KODI_NEON} \
        ${KODI_PLATFORM} ..
}

make_host() {
  :
}

makeinstall_host() {
  DESTDIR=${SYSROOT_PREFIX} cmake -DCMAKE_INSTALL_COMPONENT="kodi-addon-dev" -P cmake_install.cmake

  # more binaddons cross compile badness meh
  sed -e "s:INCLUDE_DIR /usr/include/kodi:INCLUDE_DIR ${SYSROOT_PREFIX}/usr/include/kodi:g" \
      -e "s:CMAKE_MODULE_PATH /usr/lib/kodi /usr/share/kodi/cmake:CMAKE_MODULE_PATH ${SYSROOT_PREFIX}/usr/share/kodi/cmake:g" \
      -i ${SYSROOT_PREFIX}/usr/lib/kodi/cmake/KodiConfig.cmake
}

pre_configure_target() {
  export LIBS="${LIBS} -lncurses"
}

post_makeinstall_target() {
  # skin.estuary is re-installed by the kodi-theme-Estuary package;
  # versioncheck is pointless on a read-only image
  mkdir -p ${INSTALL}/.noinstall
    mv ${INSTALL}/usr/share/kodi/addons/skin.estuary \
       ${INSTALL}/usr/share/kodi/addons/service.xbmc.versioncheck \
       ${INSTALL}/.noinstall

  rm -rf ${INSTALL}/usr/bin/kodi
  rm -rf ${INSTALL}/usr/bin/kodi-standalone
  rm -rf ${INSTALL}/usr/bin/xbmc
  rm -rf ${INSTALL}/usr/bin/xbmc-standalone
  rm -rf ${INSTALL}/usr/share/kodi/cmake
  rm -rf ${INSTALL}/usr/share/applications
  rm -rf ${INSTALL}/usr/share/icons
  rm -rf ${INSTALL}/usr/share/pixmaps
  rm -rf ${INSTALL}/usr/share/xsessions

  # kodi-config seeds /storage/.kodi/userdata on first run (invoked by the
  # plex-kodi launcher); kodi.conf documents the env the launcher sources
  mkdir -p ${INSTALL}/usr/lib/kodi
    cp ${PKG_DIR}/scripts/kodi-config ${INSTALL}/usr/lib/kodi

    if [ "${KODI_PIPEWIRE_SUPPORT}" = "yes" ]; then
      KODI_AUDIO_ARGS="--audio-backend=pipewire"
    elif [ "${KODI_PULSEAUDIO_SUPPORT}" = "yes" -a "${KODI_ALSA_SUPPORT}" = "yes" ]; then
      KODI_AUDIO_ARGS="--audio-backend=alsa+pulseaudio"
    elif [ "${KODI_PULSEAUDIO_SUPPORT}" = "yes" -a "${KODI_ALSA_SUPPORT}" != "yes" ]; then
      KODI_AUDIO_ARGS="--audio-backend=pulseaudio"
    elif [ "${KODI_PULSEAUDIO_SUPPORT}" != "yes" -a "${KODI_ALSA_SUPPORT}" = "yes" ]; then
      KODI_AUDIO_ARGS="--audio-backend=alsa"
    fi

    # adjust audio output device to what was built
    sed "s/@KODI_AUDIO_ARGS@/${KODI_AUDIO_ARGS}/" ${PKG_DIR}/config/kodi.conf.in > ${INSTALL}/usr/lib/kodi/kodi.conf

    # set default display environment
    if [ "${DISPLAYSERVER}" = "x11" ]; then
      echo "DISPLAY=:0.0" >> ${INSTALL}/usr/lib/kodi/kodi.conf
    elif [ "${DISPLAYSERVER}" = "wl" ]; then
      echo "WAYLAND_DISPLAY=wayland-1" >> ${INSTALL}/usr/lib/kodi/kodi.conf
    fi

  # used by patch 100.09 to run LE-style system service addons; harmless
  mkdir -p ${INSTALL}/usr/sbin
    cp ${PKG_DIR}/scripts/service-addon-wrapper ${INSTALL}/usr/sbin

  mkdir -p ${INSTALL}/usr/bin
    cp ${PKG_DIR}/scripts/setwakeup.sh ${INSTALL}/usr/bin

  mkdir -p ${INSTALL}/usr/share/kodi/config

  # ROCKNIX publishes the system CA bundle at /run/rocknix (see the openssl
  # overlay package); Kodi needs it for HTTPS (plex.tv login/token refresh)
  ln -sf /run/rocknix/cacert.pem ${INSTALL}/usr/share/kodi/system/certs/cacert.pem

  mkdir -p ${INSTALL}/usr/share/kodi/system/settings

  # no ${PROJECT_DIR} inputs: ROCKNIX has no per-project kodi config dirs and
  # xml_merge.py aborts on missing files
  ${PKG_DIR}/scripts/xml_merge.py ${PKG_DIR}/config/guisettings.xml \
                                > ${INSTALL}/usr/share/kodi/config/guisettings.xml

  ${PKG_DIR}/scripts/xml_merge.py ${PKG_DIR}/config/sources.xml \
                                > ${INSTALL}/usr/share/kodi/config/sources.xml

  ${PKG_DIR}/scripts/xml_merge.py ${PKG_DIR}/config/advancedsettings.xml \
                                > ${INSTALL}/usr/share/kodi/system/advancedsettings.xml

  ${PKG_DIR}/scripts/xml_merge.py ${PKG_DIR}/config/appliance.xml \
                                ${PKG_APPLIANCE_XML} \
                                > ${INSTALL}/usr/share/kodi/system/settings/appliance.xml

  # addon manifest: addons listed here are auto-installed/enabled at first run.
  # peripheral.joystick is already in the stock manifest (optional=true); the
  # PM4K addon set is baked by the plex-kodi package (co-installed via PKG_EMUS).
  ADDON_MANIFEST=${INSTALL}/usr/share/kodi/system/addon-manifest.xml
  xmlstarlet ed -L -d "/addons/addon[text()='service.xbmc.versioncheck']" ${ADDON_MANIFEST}
  for _addon in script.plexmod \
                script.module.requests script.module.six script.module.kodi-six \
                script.module.urllib3 script.module.certifi script.module.idna \
                script.module.chardet; do
    xmlstarlet ed -L --subnode "/addons" -t elem -n "addon" -v "${_addon}" ${ADDON_MANIFEST}
  done

  # more binaddons cross compile badness meh
  sed -e "s:INCLUDE_DIR /usr/include/kodi:INCLUDE_DIR ${SYSROOT_PREFIX}/usr/include/kodi:g" \
      -e "s:CMAKE_MODULE_PATH /usr/lib/kodi /usr/share/kodi/cmake:CMAKE_MODULE_PATH ${SYSROOT_PREFIX}/usr/share/kodi/cmake:g" \
      -i ${SYSROOT_PREFIX}/usr/lib/kodi/cmake/KodiConfig.cmake

  # Compile kodi Python site-packages to .pyc bytecode, and remove .py source code
  python_compile ${INSTALL}/usr/lib/${PKG_PYTHON_VERSION}/site-packages/kodi

  debug_strip ${INSTALL}/usr/lib/kodi/kodi.bin
}
