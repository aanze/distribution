// SPDX-License-Identifier: GPL-2.0
// rocknix-cwb-record: feed the DPU CWB NV12 capture ring (/dev/dpu_capture0)
// into the Iris V4L2 H.264 encoder (/dev/video1), and mux the Annex-B stream
// into a standalone .mp4 with a rotation matrix so it plays landscape on any
// common player (VLC, mpv, Windows, browsers).
//   Usage: rocknix-cwb-record <out.mp4> [max_seconds] [fps] [rotate]
//   rotate: 0|90|180|270 display rotation written to the MP4 (default 90).
//   Stop early with SIGINT/SIGTERM (drains cleanly).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>
#include <linux/dma-buf.h>

struct dpucap_geom { __u32 width, height, fourcc, num_buffers;
	__u32 y_stride, y_size, uv_stride, uv_size, total_size; };
struct dpucap_expbuf { __u32 index; __s32 fd; };
struct dpucap_frame { __u32 index, sequence; __u64 timestamp_ns; };
#define DPUCAP_MAGIC 'D'
#define DPUCAP_QUERY  _IOR(DPUCAP_MAGIC, 0, struct dpucap_geom)
#define DPUCAP_EXPBUF _IOWR(DPUCAP_MAGIC, 1, struct dpucap_expbuf)
#define DPUCAP_DQBUF  _IOR(DPUCAP_MAGIC, 2, struct dpucap_frame)
#define DPUCAP_QBUF   _IOW(DPUCAP_MAGIC, 3, __u32)

#define NCAP 6
#define die(...) do { fprintf(stderr, __VA_ARGS__); exit(1); } while (0)

static volatile sig_atomic_t stop;
static void on_sig(int s) { (void)s; stop = 1; }

/* Live screenshot: the debugfs single-shot cannot run while the NV12 ring is
 * recording (one CWB engine), so rocknix-cwb-screenshot sends SIGUSR1 and the
 * recorder dumps the next dequeued ring frame as tight BGRA to LIVE_SHOT --
 * one screenshot without interrupting the recording. */
#define LIVE_SHOT "/tmp/.cwb-live-shot.bgra"
static volatile sig_atomic_t want_shot;
static void on_usr1(int s) { (void)s; want_shot = 1; }

static inline uint8_t clamp8(int v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

/* NV12 (strided) -> tight BGRA, BT.601 limited range, BGRA byte order
 * (matches the script's existing `convert bgra:` pipeline) */
static void nv12_to_bgra(uint8_t *rgb, const uint8_t *nv12, uint32_t w,
			 uint32_t h, uint32_t y_stride, uint32_t uv_stride,
			 uint32_t y_size)
{
	const uint8_t *y = nv12, *uv = nv12 + y_size;
	for (uint32_t j = 0; j < h; j++) {
		const uint8_t *yr = y + (size_t)j * y_stride;
		const uint8_t *ur = uv + (size_t)(j / 2) * uv_stride;
		uint8_t *o = rgb + (size_t)j * w * 4;
		for (uint32_t i = 0; i < w; i++) {
			int c = yr[i] - 16;
			int d = ur[i & ~1u] - 128, e = ur[(i & ~1u) + 1] - 128;
			o[i*4+0] = clamp8((298*c + 516*d + 128) >> 8);
			o[i*4+1] = clamp8((298*c - 100*d - 208*e + 128) >> 8);
			o[i*4+2] = clamp8((298*c + 409*e + 128) >> 8);
			o[i*4+3] = 0xff;
		}
	}
}

static void dump_live_shot(const struct dpucap_geom *g, const uint8_t *nv12,
			   int dmafd)
{
	struct dma_buf_sync sync = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
	uint32_t w = g->width, h = g->height;
	size_t rgbsz = (size_t)w * h * 4;
	uint8_t *rgb = malloc(rgbsz);
	static const char tmp[] = LIVE_SHOT ".part";
	int fd;

	if (!rgb) return;
	ioctl(dmafd, DMA_BUF_IOCTL_SYNC, &sync);
	nv12_to_bgra(rgb, nv12, w, h, g->y_stride, g->uv_stride, g->y_size);
	sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
	ioctl(dmafd, DMA_BUF_IOCTL_SYNC, &sync);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd >= 0) {
		ssize_t n = write(fd, rgb, rgbsz);
		close(fd);
		if (n == (ssize_t)rgbsz)
			rename(tmp, LIVE_SHOT);	/* atomic publish */
		else
			unlink(tmp);
	}
	free(rgb);
	fprintf(stderr, "live shot %ux%u -> %s\n", w, h, LIVE_SHOT);
}

static int xioctl(int fd, unsigned long req, void *p, const char *name)
{
	int r;
	do { r = ioctl(fd, req, p); } while (r < 0 && errno == EINTR);
	if (r < 0) fprintf(stderr, "%s: %s\n", name, strerror(errno));
	return r;
}
#define IOCTL(fd, req, p) xioctl(fd, req, p, #req)

static uint64_t now_ns(void)
{
	struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
	return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

/* ---------------------------------------------------------------------------
 * Minimal in-process MP4 muxer for an H.264 elementary stream.
 *
 * Layout written: [ftyp][mdat (length-prefixed AVCC samples)][moov].
 * The mdat is streamed to the output file as frames arrive; the moov (sample
 * table + avcC built from the in-band SPS/PPS) is assembled in memory and
 * appended at finalize, then the mdat size is back-patched. A display matrix
 * in tkhd carries the rotation so players show the clip landscape.
 * ------------------------------------------------------------------------- */

#define FTYP_SIZE   32			/* see write_ftyp() */
#define MDAT_DATA   (FTYP_SIZE + 8)	/* file offset of first sample byte */

/* growable byte buffer for building moov */
struct buf { uint8_t *d; size_t len, cap; };
static void buf_need(struct buf *b, size_t n)
{
	if (b->len + n <= b->cap) return;
	while (b->cap < b->len + n) b->cap = b->cap ? b->cap * 2 : 4096;
	b->d = realloc(b->d, b->cap);
	if (!b->d) die("oom\n");
}
static void put(struct buf *b, const void *p, size_t n)
{ buf_need(b, n); memcpy(b->d + b->len, p, n); b->len += n; }
static void u8b(struct buf *b, uint8_t v) { put(b, &v, 1); }
static void u16b(struct buf *b, uint16_t v)
{ uint8_t t[2] = { v >> 8, v }; put(b, t, 2); }
static void u32b(struct buf *b, uint32_t v)
{ uint8_t t[4] = { v >> 24, v >> 16, v >> 8, v }; put(b, t, 4); }
static size_t box_start(struct buf *b, const char *type)
{ size_t at = b->len; u32b(b, 0); put(b, type, 4); return at; }
static void box_end(struct buf *b, size_t at)
{ uint32_t sz = b->len - at;
  b->d[at] = sz >> 24; b->d[at+1] = sz >> 16; b->d[at+2] = sz >> 8; b->d[at+3] = sz; }

/* sample table state */
static uint32_t *samp_sz;	/* per-sample byte size in mdat */
static uint8_t  *samp_key;	/* per-sample keyframe flag */
static uint32_t  nsamp, samp_cap;
static uint8_t   sps[512], pps[512];
static int       spslen, ppslen;

static void samp_add(uint32_t sz, int key)
{
	if (nsamp == samp_cap) {
		samp_cap = samp_cap ? samp_cap * 2 : 4096;
		samp_sz  = realloc(samp_sz, samp_cap * sizeof(*samp_sz));
		samp_key = realloc(samp_key, samp_cap * sizeof(*samp_key));
		if (!samp_sz || !samp_key) die("oom\n");
	}
	samp_sz[nsamp] = sz; samp_key[nsamp] = key; nsamp++;
}

static void write_ftyp(int fd)
{
	struct buf b = {0};
	size_t at = box_start(&b, "ftyp");
	put(&b, "isom", 4);		/* major brand */
	u32b(&b, 0x200);		/* minor version */
	put(&b, "isom", 4);
	put(&b, "iso2", 4);
	put(&b, "avc1", 4);
	put(&b, "mp41", 4);
	box_end(&b, at);
	if (b.len != FTYP_SIZE) die("ftyp size %zu != %d\n", b.len, FTYP_SIZE);
	if (write(fd, b.d, b.len) != (ssize_t)b.len) die("write ftyp\n");
	free(b.d);
}

/* Parse one Annex-B access unit: capture SPS/PPS, append all other NALs as
 * 4-byte-length-prefixed (AVCC) into *out, and return whether it is a keyframe. */
static int au_to_avcc(const uint8_t *p, size_t n, struct buf *out, int *had_vcl)
{
	int key = 0;
	size_t i = 0;
	*had_vcl = 0;
	while (i + 3 < n) {
		/* find start code 00 00 01 (with optional leading 00) */
		if (!(p[i] == 0 && p[i+1] == 0 &&
		      (p[i+2] == 1 || (p[i+2] == 0 && i + 3 < n && p[i+3] == 1)))) {
			i++; continue;
		}
		size_t sc = (p[i+2] == 1) ? 3 : 4;
		size_t nal = i + sc;
		/* find next start code -> NAL end */
		size_t j = nal;
		while (j + 2 < n &&
		       !(p[j] == 0 && p[j+1] == 0 &&
		         (p[j+2] == 1 || (p[j+2] == 0 && j + 3 < n && p[j+3] == 1))))
			j++;
		size_t nlen = (j + 2 < n) ? (j - nal) : (n - nal);
		if (nlen == 0) { i = nal; continue; }
		uint8_t type = p[nal] & 0x1f;
		if (type == 7) {		/* SPS */
			if (!spslen && nlen <= sizeof(sps)) {
				memcpy(sps, p + nal, nlen); spslen = nlen;
			}
		} else if (type == 8) {		/* PPS */
			if (!ppslen && nlen <= sizeof(pps)) {
				memcpy(pps, p + nal, nlen); ppslen = nlen;
			}
		} else {			/* SEI / slice -> sample data */
			if (type == 5) key = 1;
			if (type >= 1 && type <= 5) *had_vcl = 1;
			u32b(out, (uint32_t)nlen);
			put(out, p + nal, nlen);
		}
		i = nal + nlen;
	}
	return key;
}

/* display matrix (16.16 / 2.30 fixed) for the given rotation, coded WxH. */
static void put_matrix(struct buf *b, int rot, uint32_t w, uint32_t h)
{
	int32_t m[9];
	const int32_t U = 0x00010000, W = 0x40000000;
	switch (rot) {
	case 90:  m[0]=0; m[1]=U; m[2]=0; m[3]=-U; m[4]=0; m[5]=0;
		  m[6]=(int32_t)(h<<16); m[7]=0; m[8]=W; break;
	case 180: m[0]=-U; m[1]=0; m[2]=0; m[3]=0; m[4]=-U; m[5]=0;
		  m[6]=(int32_t)(w<<16); m[7]=(int32_t)(h<<16); m[8]=W; break;
	case 270: m[0]=0; m[1]=-U; m[2]=0; m[3]=U; m[4]=0; m[5]=0;
		  m[6]=0; m[7]=(int32_t)(w<<16); m[8]=W; break;
	default:  m[0]=U; m[1]=0; m[2]=0; m[3]=0; m[4]=U; m[5]=0;
		  m[6]=0; m[7]=0; m[8]=W; break;
	}
	for (int i = 0; i < 9; i++) u32b(b, (uint32_t)m[i]);
}

static void write_moov(int fd, uint32_t cw, uint32_t ch, int fps, int rot)
{
	const uint32_t mts = 90000;		/* media timescale */
	const uint32_t delta = fps > 0 ? mts / fps : 3000;
	const uint32_t mdur = nsamp * delta;	/* media duration */
	const uint32_t vts = 1000;		/* movie timescale */
	const uint32_t vdur = fps > 0 ? (uint32_t)((uint64_t)nsamp * 1000 / fps) : 0;
	/* presentation size after rotation */
	struct buf b = {0};
	size_t moov, trak, mdia, minf, stbl, stsd, avc1, avcC, e;

	moov = box_start(&b, "moov");

	/* mvhd */
	e = box_start(&b, "mvhd"); u32b(&b, 0); u32b(&b, 0); u32b(&b, 0);
	u32b(&b, vts); u32b(&b, vdur); u32b(&b, 0x00010000); u16b(&b, 0x0100);
	u16b(&b, 0); u32b(&b, 0); u32b(&b, 0);
	put_matrix(&b, 0, cw, ch);		/* movie matrix = identity */
	for (int i = 0; i < 6; i++) u32b(&b, 0);
	u32b(&b, 2);				/* next track id */
	box_end(&b, e);

	trak = box_start(&b, "trak");

	/* tkhd (flags 0x7 = enabled|in-movie|in-preview) */
	e = box_start(&b, "tkhd"); u8b(&b, 0); u8b(&b, 0); u8b(&b, 0); u8b(&b, 0x7);
	u32b(&b, 0); u32b(&b, 0); u32b(&b, 1); u32b(&b, 0); u32b(&b, vdur);
	u32b(&b, 0); u32b(&b, 0); u16b(&b, 0); u16b(&b, 0); u16b(&b, 0); u16b(&b, 0);
	put_matrix(&b, rot, cw, ch);
	/*
	 * tkhd width/height are the CODED dims, not the post-rotation size: the
	 * matrix above does the rotation. This is the Android/ffmpeg convention and
	 * is what rotates correctly across players (VLC included). Setting these to
	 * the swapped size instead makes some players double-transform and squish.
	 */
	u32b(&b, cw << 16); u32b(&b, ch << 16);	/* coded w/h (16.16) */
	box_end(&b, e);

	mdia = box_start(&b, "mdia");
	e = box_start(&b, "mdhd"); u32b(&b, 0); u32b(&b, 0); u32b(&b, 0);
	u32b(&b, mts); u32b(&b, mdur); u16b(&b, 0x55c4); u16b(&b, 0); box_end(&b, e);
	e = box_start(&b, "hdlr"); u32b(&b, 0); u32b(&b, 0); put(&b, "vide", 4);
	u32b(&b, 0); u32b(&b, 0); u32b(&b, 0); put(&b, "VideoHandler", 13);
	box_end(&b, e);

	minf = box_start(&b, "minf");
	e = box_start(&b, "vmhd"); u8b(&b, 0); u8b(&b, 0); u8b(&b, 0); u8b(&b, 1);
	u16b(&b, 0); u16b(&b, 0); u16b(&b, 0); u16b(&b, 0); box_end(&b, e);
	e = box_start(&b, "dinf");
	{ size_t dref = box_start(&b, "dref"); u32b(&b, 0); u32b(&b, 1);
	  size_t url = box_start(&b, "url "); u8b(&b, 0); u8b(&b, 0); u8b(&b, 0);
	  u8b(&b, 1); box_end(&b, url); box_end(&b, dref); }
	box_end(&b, e);

	stbl = box_start(&b, "stbl");

	stsd = box_start(&b, "stsd"); u32b(&b, 0); u32b(&b, 1);
	avc1 = box_start(&b, "avc1");
	for (int i = 0; i < 6; i++) u8b(&b, 0);	/* reserved */
	u16b(&b, 1);				/* data ref index */
	u16b(&b, 0); u16b(&b, 0); u32b(&b, 0); u32b(&b, 0); u32b(&b, 0);
	u16b(&b, cw); u16b(&b, ch);
	u32b(&b, 0x00480000); u32b(&b, 0x00480000);	/* 72 dpi h/v */
	u32b(&b, 0); u16b(&b, 1);		/* frame count */
	for (int i = 0; i < 32; i++) u8b(&b, 0);	/* compressorname */
	u16b(&b, 0x0018);			/* depth */
	u16b(&b, 0xffff);			/* pre-defined */
	avcC = box_start(&b, "avcC");
	u8b(&b, 1);				/* configurationVersion */
	u8b(&b, spslen > 1 ? sps[1] : 0x42);	/* profile */
	u8b(&b, spslen > 2 ? sps[2] : 0);	/* profile compat */
	u8b(&b, spslen > 3 ? sps[3] : 0x1f);	/* level */
	u8b(&b, 0xff);				/* lengthSizeMinusOne=3 */
	u8b(&b, 0xe1);				/* numSPS=1 */
	u16b(&b, spslen); put(&b, sps, spslen);
	u8b(&b, 1);				/* numPPS=1 */
	u16b(&b, ppslen); put(&b, pps, ppslen);
	box_end(&b, avcC);
	box_end(&b, avc1);
	box_end(&b, stsd);

	/* stts: constant frame duration */
	e = box_start(&b, "stts"); u32b(&b, 0); u32b(&b, 1);
	u32b(&b, nsamp); u32b(&b, delta); box_end(&b, e);

	/* stss: sync samples */
	{ uint32_t nk = 0; for (uint32_t i = 0; i < nsamp; i++) nk += samp_key[i];
	  e = box_start(&b, "stss"); u32b(&b, 0); u32b(&b, nk);
	  for (uint32_t i = 0; i < nsamp; i++) if (samp_key[i]) u32b(&b, i + 1);
	  box_end(&b, e); }

	/* stsc: all samples in one chunk */
	e = box_start(&b, "stsc"); u32b(&b, 0); u32b(&b, 1);
	u32b(&b, 1); u32b(&b, nsamp); u32b(&b, 1); box_end(&b, e);

	/* stsz: per-sample sizes */
	e = box_start(&b, "stsz"); u32b(&b, 0); u32b(&b, 0); u32b(&b, nsamp);
	for (uint32_t i = 0; i < nsamp; i++) u32b(&b, samp_sz[i]); box_end(&b, e);

	/* stco: single chunk offset */
	e = box_start(&b, "stco"); u32b(&b, 0); u32b(&b, 1);
	u32b(&b, MDAT_DATA); box_end(&b, e);

	box_end(&b, stbl);
	box_end(&b, minf);
	box_end(&b, mdia);
	box_end(&b, trak);
	box_end(&b, moov);

	if (write(fd, b.d, b.len) != (ssize_t)b.len) die("write moov\n");
	free(b.d);
}

/* converter mode for rocknix-cwb-screenshot: the debugfs NV12 single-shot
 * frame.raw -> tight BGRA that ImageMagick can ingest (`convert bgra:`).
 * The XRGB shot path stopped completing on the 7.1 DPU (WB done never fires
 * without the CDM in the chain), so the shot now rides the proven NV12 path
 * and converts here. */
static int convert_mode(int argc, char **argv)
{
	if (argc != 9)
		die("usage: --nv12-to-bgra <in> <out> <w> <h> <ystride> <uvstride> <ysize>\n");
	const char *in = argv[2], *out = argv[3];
	uint32_t w = atoi(argv[4]), h = atoi(argv[5]);
	uint32_t ys = atoi(argv[6]), uvs = atoi(argv[7]), ysz = atoi(argv[8]);
	size_t insz = (size_t)ysz + (size_t)uvs * (h / 2);
	size_t outsz = (size_t)w * h * 4;
	uint8_t *nv12 = malloc(insz), *rgb = malloc(outsz);
	FILE *f;

	if (!nv12 || !rgb) die("oom\n");
	f = fopen(in, "rb");
	if (!f || fread(nv12, 1, insz, f) != insz)
		die("read %s\n", in);
	fclose(f);
	nv12_to_bgra(rgb, nv12, w, h, ys, uvs, ysz);
	f = fopen(out, "wb");
	if (!f || fwrite(rgb, 1, outsz, f) != outsz)
		die("write %s\n", out);
	fclose(f);
	free(nv12); free(rgb);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc > 1 && !strcmp(argv[1], "--nv12-to-bgra"))
		return convert_mode(argc, argv);
	if (argc < 2) die("usage: %s <out.mp4> [seconds] [fps] [rotate]\n", argv[0]);
	const char *outpath = argv[1];
	double max_s = argc > 2 ? atof(argv[2]) : 0;
	int fps = argc > 3 ? atoi(argv[3]) : 30;
	int rot = argc > 4 ? atoi(argv[4]) : 270;
	if (rot != 0 && rot != 90 && rot != 180 && rot != 270) rot = 90;
	uint64_t frame_interval = fps > 0 ? 1000000000ull / fps : 0;

	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);
	signal(SIGUSR1, on_usr1);

	int cap = open("/dev/dpu_capture0", O_RDWR | O_CLOEXEC);
	if (cap < 0) die("open dpu_capture0: %s\n", strerror(errno));

	struct dpucap_geom g = {0};
	if (IOCTL(cap, DPUCAP_QUERY, &g) < 0) die("QUERY\n");
	fprintf(stderr, "capture %ux%u nv12 ystride=%u size=%u nbuf=%u rot=%d\n",
		g.width, g.height, g.y_stride, g.total_size, g.num_buffers, rot);

	int dfd[16];
	for (unsigned i = 0; i < g.num_buffers; i++) {
		struct dpucap_expbuf e = { .index = i };
		if (IOCTL(cap, DPUCAP_EXPBUF, &e) < 0) die("EXPBUF %u\n", i);
		dfd[i] = e.fd;
	}

	/* CPU view of the ring for SIGUSR1 live screenshots; best-effort (a
	 * failed mmap only disables the live-shot feature, not recording) */
	uint8_t *rptr[16] = {0};
	for (unsigned i = 0; i < g.num_buffers; i++) {
		rptr[i] = mmap(NULL, g.total_size, PROT_READ, MAP_SHARED, dfd[i], 0);
		if (rptr[i] == MAP_FAILED) rptr[i] = NULL;
	}

	int enc = open("/dev/video1", O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (enc < 0) die("open video1: %s\n", strerror(errno));

	struct v4l2_format ofmt = {0};
	ofmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	ofmt.fmt.pix_mp.width = g.width;
	ofmt.fmt.pix_mp.height = g.height;
	ofmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
	ofmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
	if (IOCTL(enc, VIDIOC_S_FMT, &ofmt) < 0) die("S_FMT OUTPUT\n");
	int o_planes = ofmt.fmt.pix_mp.num_planes;
	uint32_t o_sizeimage = ofmt.fmt.pix_mp.plane_fmt[0].sizeimage;
	fprintf(stderr, "enc OUTPUT NV12 planes=%d sizeimage=%u (buf=%u)\n",
		o_planes, o_sizeimage, g.total_size);

	/*
	 * Landscape via a tkhd rotation matrix. The coded frame stays portrait
	 * (what the panel/CWB produces); the matrix tells the player to rotate it
	 * to landscape. tkhd width/height are the CODED dims (the Android/ffmpeg
	 * convention) -- the matrix does the rotation -- which is what plays
	 * correctly across players including VLC. (Encoder-side V4L2_CID_ROTATE was
	 * tried but this iris build treats the swapped size as scaling and rejects
	 * the input with EIO, so it is not used.)
	 */
	struct v4l2_control ctrl;
	struct v4l2_format cfmt = {0};
	cfmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	cfmt.fmt.pix_mp.width  = g.width;
	cfmt.fmt.pix_mp.height = g.height;
	cfmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
	cfmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
	if (IOCTL(enc, VIDIOC_S_FMT, &cfmt) < 0) die("S_FMT CAPTURE\n");
	int c_planes = cfmt.fmt.pix_mp.num_planes;
	fprintf(stderr, "enc CAPTURE H264 coded=%ux%u rot(matrix)=%d\n",
		g.width, g.height, rot);

	ctrl.id = V4L2_CID_MPEG_VIDEO_BITRATE; ctrl.value = 12000000;
	ioctl(enc, VIDIOC_S_CTRL, &ctrl);
	ctrl.id = V4L2_CID_MPEG_VIDEO_GOP_SIZE; ctrl.value = fps;
	ioctl(enc, VIDIOC_S_CTRL, &ctrl);

	struct v4l2_requestbuffers orb = {0};
	orb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	orb.memory = V4L2_MEMORY_DMABUF;
	orb.count = g.num_buffers;
	if (IOCTL(enc, VIDIOC_REQBUFS, &orb) < 0) die("REQBUFS OUTPUT\n");

	struct v4l2_requestbuffers crb = {0};
	crb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	crb.memory = V4L2_MEMORY_MMAP;
	crb.count = NCAP;
	if (IOCTL(enc, VIDIOC_REQBUFS, &crb) < 0) die("REQBUFS CAPTURE\n");
	int ncap = crb.count;

	void *cap_ptr[NCAP];
	for (int i = 0; i < ncap; i++) {
		struct v4l2_plane planes[VIDEO_MAX_PLANES] = {0};
		struct v4l2_buffer b = {0};
		b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
		b.memory = V4L2_MEMORY_MMAP;
		b.index = i; b.length = c_planes; b.m.planes = planes;
		if (IOCTL(enc, VIDIOC_QUERYBUF, &b) < 0) die("QUERYBUF CAP %d\n", i);
		cap_ptr[i] = mmap(NULL, planes[0].length, PROT_READ | PROT_WRITE,
				  MAP_SHARED, enc, planes[0].m.mem_offset);
		if (cap_ptr[i] == MAP_FAILED) die("mmap cap %d\n", i);
		if (IOCTL(enc, VIDIOC_QBUF, &b) < 0) die("QBUF CAP %d\n", i);
	}

	int type;
	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	if (IOCTL(enc, VIDIOC_STREAMON, &type) < 0) die("STREAMON OUTPUT\n");
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (IOCTL(enc, VIDIOC_STREAMON, &type) < 0) die("STREAMON CAPTURE\n");

	int outfd = open(outpath, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (outfd < 0) die("open out: %s\n", strerror(errno));
	write_ftyp(outfd);
	/* mdat header (size back-patched at finalize) */
	{ uint8_t hdr[8] = { 0,0,0,0,'m','d','a','t' };
	  if (write(outfd, hdr, 8) != 8) die("write mdat hdr\n"); }
	uint64_t mdat_bytes = 0;

	uint64_t t0 = now_ns(), last_frame = 0, nframes = 0;

	while (!stop) {
		if (max_s > 0 && (now_ns() - t0) > (uint64_t)(max_s * 1e9))
			break;

		struct pollfd pfd[2] = {
			{ .fd = cap, .events = POLLIN },
			{ .fd = enc, .events = POLLIN },
		};
		poll(pfd, 2, 100);

		if (pfd[0].revents & POLLIN) {
			struct dpucap_frame fr;
			if (ioctl(cap, DPUCAP_DQBUF, &fr) == 0) {
				if (want_shot) {
					want_shot = 0;
					if (rptr[fr.index])
						dump_live_shot(&g, rptr[fr.index],
							       dfd[fr.index]);
				}
				uint64_t t = now_ns();
				if (frame_interval && (t - last_frame) < frame_interval) {
					ioctl(cap, DPUCAP_QBUF, &fr.index);
				} else {
					last_frame = t;
					struct v4l2_plane pl[VIDEO_MAX_PLANES] = {0};
					struct v4l2_buffer b = {0};
					b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
					b.memory = V4L2_MEMORY_DMABUF;
					b.index = fr.index;
					b.length = o_planes;
					b.m.planes = pl;
					b.timestamp.tv_sec = t / 1000000000ull;
					b.timestamp.tv_usec = (t % 1000000000ull) / 1000;
					pl[0].m.fd = dfd[fr.index];
					pl[0].bytesused = o_sizeimage;
					pl[0].length = g.total_size;
					if (o_planes > 1) {
						pl[1].m.fd = dfd[fr.index];
						pl[1].bytesused = g.uv_size;
						pl[1].length = g.total_size;
						pl[1].data_offset = g.y_size;
					}
					if (ioctl(enc, VIDIOC_QBUF, &b) < 0) {
						fprintf(stderr, "QBUF OUT idx%u: %s\n",
							fr.index, strerror(errno));
						ioctl(cap, DPUCAP_QBUF, &fr.index);
					}
				}
			}
		}

		for (;;) {	/* reclaim consumed OUTPUT -> release to ring */
			struct v4l2_plane pl[VIDEO_MAX_PLANES] = {0};
			struct v4l2_buffer b = {0};
			b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			b.memory = V4L2_MEMORY_DMABUF;
			b.length = o_planes; b.m.planes = pl;
			if (ioctl(enc, VIDIOC_DQBUF, &b) < 0) break;
			ioctl(cap, DPUCAP_QBUF, &b.index);
		}

		for (;;) {	/* drain encoded bitstream -> mux to mp4 */
			struct v4l2_plane pl[VIDEO_MAX_PLANES] = {0};
			struct v4l2_buffer b = {0};
			b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.length = c_planes; b.m.planes = pl;
			if (ioctl(enc, VIDIOC_DQBUF, &b) < 0) break;
			if (pl[0].bytesused) {
				struct buf au = {0};
				int had_vcl, key;
				key = au_to_avcc(cap_ptr[b.index], pl[0].bytesused,
						 &au, &had_vcl);
				if (had_vcl && au.len) {
					write(outfd, au.d, au.len);
					mdat_bytes += au.len;
					samp_add((uint32_t)au.len, key);
					nframes++;
				}
				free(au.d);
			}
			ioctl(enc, VIDIOC_QBUF, &b);
		}
	}

	struct v4l2_encoder_cmd ec = { .cmd = V4L2_ENC_CMD_STOP };
	ioctl(enc, VIDIOC_ENCODER_CMD, &ec);
	for (int tries = 0; tries < 100; tries++) {
		struct v4l2_plane pl[VIDEO_MAX_PLANES] = {0};
		struct v4l2_buffer b = {0};
		b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
		b.memory = V4L2_MEMORY_MMAP;
		b.length = c_planes; b.m.planes = pl;
		if (ioctl(enc, VIDIOC_DQBUF, &b) < 0) {
			if (errno == EAGAIN) { usleep(10000); continue; }
			break;
		}
		if (pl[0].bytesused) {
			struct buf au = {0};
			int had_vcl, key;
			key = au_to_avcc(cap_ptr[b.index], pl[0].bytesused, &au, &had_vcl);
			if (had_vcl && au.len) {
				write(outfd, au.d, au.len);
				mdat_bytes += au.len;
				samp_add((uint32_t)au.len, key);
				nframes++;
			}
			free(au.d);
		}
		if (b.flags & V4L2_BUF_FLAG_LAST) break;
		ioctl(enc, VIDIOC_QBUF, &b);
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;  ioctl(enc, VIDIOC_STREAMOFF, &type);
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; ioctl(enc, VIDIOC_STREAMOFF, &type);

	/* finalize mp4: back-patch mdat size, append moov */
	if (nsamp && spslen && ppslen) {
		uint32_t mdat_sz = (uint32_t)(8 + mdat_bytes);
		uint8_t szb[4] = { mdat_sz >> 24, mdat_sz >> 16, mdat_sz >> 8, mdat_sz };
		lseek(outfd, FTYP_SIZE, SEEK_SET);
		write(outfd, szb, 4);
		lseek(outfd, 0, SEEK_END);
		write_moov(outfd, g.width, g.height, fps, rot);
	} else {
		fprintf(stderr, "no samples/SPS/PPS; mp4 not finalized\n");
	}

	close(outfd);
	for (unsigned i = 0; i < g.num_buffers; i++) close(dfd[i]);
	close(enc);
	close(cap);
	fprintf(stderr, "done: %llu frames, %llu mdat bytes -> %s\n",
		(unsigned long long)nframes, (unsigned long long)mdat_bytes, outpath);
	return 0;
}
