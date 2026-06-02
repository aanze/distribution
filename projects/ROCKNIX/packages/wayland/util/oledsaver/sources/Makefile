# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

CC ?= cc
WAYLAND_SCANNER ?= wayland-scanner

# wlr-layer-shell references xdg_popup (via get_popup), so the xdg-shell
# protocol code must be linked in too even though we never create popups.
PROTOS = wlr-layer-shell-unstable-v1 xdg-shell
PROTO_SRC = $(addsuffix -protocol.c, $(PROTOS))
PROTO_HDR = $(addsuffix -client-protocol.h, $(PROTOS))

.PHONY: all install clean
all: oledsaver

%-client-protocol.h: %.xml
	$(WAYLAND_SCANNER) client-header $< $@

%-protocol.c: %.xml
	$(WAYLAND_SCANNER) private-code $< $@

oledsaver: oledsaver.c $(PROTO_SRC) $(PROTO_HDR)
	$(CC) $(CFLAGS) $(LDFLAGS) -I. -o $@ oledsaver.c $(PROTO_SRC) -lwayland-client -lrt

install: oledsaver
	install -d $(DESTDIR)/usr/bin
	install -m 0755 oledsaver $(DESTDIR)/usr/bin/oledsaver

clean:
	rm -f oledsaver $(PROTO_SRC) $(PROTO_HDR)
