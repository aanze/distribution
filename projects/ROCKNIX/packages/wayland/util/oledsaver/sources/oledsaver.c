/* SPDX-License-Identifier: GPL-2.0 */
/* Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX) */
/*
 * oledsaver - a tiny wlr-layer-shell OLED anti-image-retention screensaver.
 *
 * Draws a mostly-black fullscreen overlay with a band of grayscale noise that
 * slowly sweeps across the panel (à la the AYN Android "pixel refresh"). Most
 * of the screen stays black (OLED pixels off => near-zero panel power) and only
 * a small band is lit/animated, so it is cheap.
 *
 * Key design points:
 *   - OVERLAY layer => painted on top of EmulationStation.
 *   - EMPTY input region => the surface is input-transparent, so button presses
 *     still reach ES underneath. ES then cancels its own screensaver and fires
 *     the "screensaver-stop" scripting event, which kills us. Single press, no
 *     focus stealing.
 *   - Throttled to ~OLEDSAVER_FPS frames/s (poll loop), not the 120 Hz panel.
 *
 * Launched/killed by the ES screensaver-start/-stop event scripts.
 */

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

struct buffer {
	struct wl_buffer *wl_buffer;
	uint32_t *data;
	size_t size;
	int busy;
};

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wl_surface *surface;
static struct zwlr_layer_surface_v1 *layer_surface;

static int width = 0, height = 0;
static int configured = 0;
static volatile sig_atomic_t running = 1;

static struct buffer buffers[2];

/* Animation parameters (overridable via env) */
static int   fps = 30;
static double band_frac = 0.22;   /* band height as fraction of screen */
static double sweep_seconds = 6.0; /* time for one full top->bottom pass */

/* fast PRNG */
static uint32_t rng_state = 0x2545F491u;
static inline uint32_t xorshift32(void) {
	uint32_t x = rng_state;
	x ^= x << 13; x ^= x >> 17; x ^= x << 5;
	return rng_state = x;
}

static int64_t now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void handle_sig(int s) { (void)s; running = 0; }

/* ---- shm buffer ---- */
static int anon_shm(size_t size) {
	char name[64];
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	snprintf(name, sizeof(name), "/oledsaver-%x-%x",
		(unsigned)getpid(), (unsigned)ts.tv_nsec);
	int fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (fd < 0) return -1;
	shm_unlink(name);
	if (ftruncate(fd, size) < 0) { close(fd); return -1; }
	return fd;
}

static void buffer_release(void *data, struct wl_buffer *wl_buffer) {
	(void)wl_buffer;
	((struct buffer *)data)->busy = 0;
}
static const struct wl_buffer_listener buffer_listener = { .release = buffer_release };

static void destroy_buffer(struct buffer *b) {
	if (b->wl_buffer) wl_buffer_destroy(b->wl_buffer);
	if (b->data && b->data != MAP_FAILED) munmap(b->data, b->size);
	memset(b, 0, sizeof(*b));
}

static int create_buffer(struct buffer *b, int w, int h) {
	size_t stride = (size_t)w * 4;
	size_t size = stride * h;
	int fd = anon_shm(size);
	if (fd < 0) return -1;
	void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (map == MAP_FAILED) { close(fd); return -1; }
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
	b->wl_buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride,
		WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	b->data = map;
	b->size = size;
	b->busy = 0;
	wl_buffer_add_listener(b->wl_buffer, &buffer_listener, b);
	return 0;
}

static struct buffer *next_buffer(void) {
	for (int i = 0; i < 2; i++) {
		if (!buffers[i].wl_buffer) {
			if (create_buffer(&buffers[i], width, height) < 0) return NULL;
		}
		if (!buffers[i].busy) return &buffers[i];
	}
	return NULL; /* both in flight, skip this frame */
}

/* current sweep position (top of band), advanced each frame */
static double band_y = 0.0;
static double band_dy = 0.0;

static void draw(struct buffer *b) {
	int band_h = (int)(height * band_frac);
	if (band_h < 1) band_h = 1;
	int travel = height - band_h;
	if (travel < 1) travel = 1;
	if (band_dy == 0.0)
		band_dy = (double)travel / (sweep_seconds * fps);

	/* black everywhere */
	memset(b->data, 0, b->size);

	int y0 = (int)band_y;
	if (y0 < 0) y0 = 0;
	if (y0 > travel) y0 = travel;

	for (int y = y0; y < y0 + band_h && y < height; y++) {
		uint32_t *row = b->data + (size_t)y * width;
		for (int x = 0; x < width; x++) {
			uint32_t g = xorshift32() & 0xFF;
			row[x] = 0xFF000000u | (g << 16) | (g << 8) | g;
		}
	}

	/* advance + bounce */
	band_y += band_dy;
	if (band_y >= travel) { band_y = travel; band_dy = -band_dy; }
	else if (band_y <= 0)  { band_y = 0;      band_dy = -band_dy; }
}

static void render(void) {
	struct buffer *b = next_buffer();
	if (!b) return;
	draw(b);
	b->busy = 1;
	wl_surface_attach(surface, b->wl_buffer, 0, 0);
	wl_surface_damage_buffer(surface, 0, 0, width, height);
	wl_surface_commit(surface);
}

/* ---- layer surface ---- */
static void ls_configure(void *data, struct zwlr_layer_surface_v1 *ls,
		uint32_t serial, uint32_t w, uint32_t h) {
	(void)data;
	zwlr_layer_surface_v1_ack_configure(ls, serial);
	if ((int)w != width || (int)h != height) {
		width = (int)w; height = (int)h;
		destroy_buffer(&buffers[0]);
		destroy_buffer(&buffers[1]);
		band_y = 0.0; band_dy = 0.0;
	}
	configured = 1;
	render();
}
static void ls_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
	(void)data; (void)ls; running = 0;
}
static const struct zwlr_layer_surface_v1_listener ls_listener = {
	.configure = ls_configure,
	.closed = ls_closed,
};

/* ---- registry ---- */
static void reg_global(void *data, struct wl_registry *reg, uint32_t name,
		const char *iface, uint32_t version) {
	(void)data; (void)version;
	if (!strcmp(iface, wl_compositor_interface.name))
		compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, wl_shm_interface.name))
		shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
	else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
		layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
}
static void reg_remove(void *data, struct wl_registry *reg, uint32_t name) {
	(void)data; (void)reg; (void)name;
}
static const struct wl_registry_listener reg_listener = {
	.global = reg_global, .global_remove = reg_remove,
};

int main(void) {
	const char *e;
	if ((e = getenv("OLEDSAVER_FPS")))   { int v = atoi(e); if (v >= 1 && v <= 120) fps = v; }
	if ((e = getenv("OLEDSAVER_BAND")))  { double v = atof(e); if (v > 0.02 && v < 1.0) band_frac = v; }
	if ((e = getenv("OLEDSAVER_SWEEP"))) { double v = atof(e); if (v >= 1.0 && v <= 120.0) sweep_seconds = v; }
	rng_state ^= (uint32_t)now_ms() | 1u;

	signal(SIGINT, handle_sig);
	signal(SIGTERM, handle_sig);

	display = wl_display_connect(NULL);
	if (!display) { fprintf(stderr, "oledsaver: cannot connect to wayland\n"); return 1; }

	struct wl_registry *reg = wl_display_get_registry(display);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(display);

	if (!compositor || !shm || !layer_shell) {
		fprintf(stderr, "oledsaver: missing wayland globals (compositor=%p shm=%p layer_shell=%p)\n",
			(void*)compositor, (void*)shm, (void*)layer_shell);
		return 1;
	}

	surface = wl_compositor_create_surface(compositor);

	/* input-transparent: empty input region => events pass through to ES */
	struct wl_region *empty = wl_compositor_create_region(compositor);
	wl_surface_set_input_region(surface, empty);
	wl_region_destroy(empty);

	layer_surface = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface,
		NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "oledsaver");
	zwlr_layer_surface_v1_set_anchor(layer_surface,
		ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
		ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, -1);
	zwlr_layer_surface_v1_set_size(layer_surface, 0, 0);
	zwlr_layer_surface_v1_add_listener(layer_surface, &ls_listener, NULL);
	wl_surface_commit(surface);

	int fd = wl_display_get_fd(display);
	int frame_ms = 1000 / fps;
	int64_t last = 0;

	while (running) {
		while (wl_display_prepare_read(display) != 0)
			wl_display_dispatch_pending(display);
		wl_display_flush(display);

		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		int n = poll(&pfd, 1, frame_ms);
		if (n > 0 && (pfd.revents & POLLIN))
			wl_display_read_events(display);
		else
			wl_display_cancel_read(display);
		if (wl_display_dispatch_pending(display) < 0) break;

		if (configured) {
			int64_t t = now_ms();
			if (t - last >= frame_ms) { render(); last = t; }
		}
	}

	destroy_buffer(&buffers[0]);
	destroy_buffer(&buffers[1]);
	if (layer_surface) zwlr_layer_surface_v1_destroy(layer_surface);
	if (surface) wl_surface_destroy(surface);
	wl_display_disconnect(display);
	return 0;
}
