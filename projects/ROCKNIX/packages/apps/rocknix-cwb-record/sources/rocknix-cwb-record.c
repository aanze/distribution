// SPDX-License-Identifier: GPL-2.0
// rocknix-cwb-record: feed the DPU CWB NV12 capture ring (/dev/dpu_capture0)
// into the Iris V4L2 H.264 encoder (/dev/video1), writing an Annex-B .h264.
//   Usage: rocknix-cwb-record <out.h264> [max_seconds] [fps]
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

int main(int argc, char **argv)
{
	if (argc < 2) die("usage: %s <out.h264> [seconds] [fps]\n", argv[0]);
	const char *outpath = argv[1];
	double max_s = argc > 2 ? atof(argv[2]) : 0;
	int fps = argc > 3 ? atoi(argv[3]) : 30;
	uint64_t frame_interval = fps > 0 ? 1000000000ull / fps : 0;

	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);

	int cap = open("/dev/dpu_capture0", O_RDWR | O_CLOEXEC);
	if (cap < 0) die("open dpu_capture0: %s\n", strerror(errno));

	struct dpucap_geom g = {0};
	if (IOCTL(cap, DPUCAP_QUERY, &g) < 0) die("QUERY\n");
	fprintf(stderr, "capture %ux%u nv12 ystride=%u size=%u nbuf=%u\n",
		g.width, g.height, g.y_stride, g.total_size, g.num_buffers);

	int dfd[16];
	for (unsigned i = 0; i < g.num_buffers; i++) {
		struct dpucap_expbuf e = { .index = i };
		if (IOCTL(cap, DPUCAP_EXPBUF, &e) < 0) die("EXPBUF %u\n", i);
		dfd[i] = e.fd;
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

	struct v4l2_format cfmt = {0};
	cfmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	cfmt.fmt.pix_mp.width = g.width;
	cfmt.fmt.pix_mp.height = g.height;
	cfmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
	cfmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
	if (IOCTL(enc, VIDIOC_S_FMT, &cfmt) < 0) die("S_FMT CAPTURE\n");
	int c_planes = cfmt.fmt.pix_mp.num_planes;

	struct v4l2_control ctrl;
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

	int outfd = open(outpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (outfd < 0) die("open out: %s\n", strerror(errno));

	uint64_t t0 = now_ns(), last_frame = 0, nframes = 0, nbytes = 0;

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

		for (;;) {	/* drain encoded bitstream */
			struct v4l2_plane pl[VIDEO_MAX_PLANES] = {0};
			struct v4l2_buffer b = {0};
			b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.length = c_planes; b.m.planes = pl;
			if (ioctl(enc, VIDIOC_DQBUF, &b) < 0) break;
			if (pl[0].bytesused) {
				write(outfd, cap_ptr[b.index], pl[0].bytesused);
				nbytes += pl[0].bytesused; nframes++;
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
			write(outfd, cap_ptr[b.index], pl[0].bytesused);
			nbytes += pl[0].bytesused; nframes++;
		}
		if (b.flags & V4L2_BUF_FLAG_LAST) break;
		ioctl(enc, VIDIOC_QBUF, &b);
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;  ioctl(enc, VIDIOC_STREAMOFF, &type);
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; ioctl(enc, VIDIOC_STREAMOFF, &type);
	close(outfd);
	for (unsigned i = 0; i < g.num_buffers; i++) close(dfd[i]);
	close(enc);
	close(cap);
	fprintf(stderr, "done: %llu encoded frames, %llu bytes -> %s\n",
		(unsigned long long)nframes, (unsigned long long)nbytes, outpath);
	return 0;
}
