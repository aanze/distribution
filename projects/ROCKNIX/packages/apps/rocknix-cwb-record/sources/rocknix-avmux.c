// SPDX-License-Identifier: GPL-2.0
// rocknix-avmux: merge the video-only MP4 written by rocknix-cwb-record with
// a raw PCM system-audio capture into the final clip. The H.264 track is
// stream-copied (bit-exact, rotation matrix preserved); the PCM is encoded
// to AAC with the native libavcodec encoder and both tracks are written
// interleaved through the movenc-family "ipod" muxer (the only MP4 muxer
// enabled in this ffmpeg build).
//
//   rocknix-avmux <video.mp4> <audio.pcm> <out.mp4> [trim_ms]
//   rocknix-avmux --now
//
// audio.pcm is s16le / 48000 Hz / 2ch as produced by `parec --raw`.
// trim_ms (signed): how much the audio capture started BEFORE video sample 0
// (the wrapper computes vt0-at0); positive skips PCM from the head, negative
// inserts leading silence. The AAC 1024-sample priming delay needs NO
// compensation here: the encoder back-shifts the first packet's pts and the
// muxer writes a matching edit list (verified: first pts=-1024 + elst).
// `--now` prints CLOCK_MONOTONIC ns and is used by the wrapper to stamp the
// audio start time next to the recorder's /tmp/.screenrecord.vt0 anchor.
//
// Discipline: inputs are never modified; on ANY failure the (partial) output
// is unlinked and the exit code is nonzero -- the wrapper then falls back to
// keeping the video-only clip. Works against lavf 60 (FFmpeg 6.x, current
// sysroot) and 61+ (FFmpeg 7.x, next clean build) -- see the version gate.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>
#include <unistd.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>

#define ARATE 48000
#define ACH   2
#define ABPS  (2 * ACH)			/* bytes per PCM frame (s16le stereo) */
#define AAC_FRAME 1024			/* native AAC frame size (fsz fallback) */

static const char *g_out;
static AVFormatContext *g_oc;

static void die(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	if (g_oc && !(g_oc->oformat->flags & AVFMT_NOFILE) && g_oc->pb)
		avio_closep(&g_oc->pb);
	if (g_out)
		unlink(g_out);
	exit(1);
}

/* PCM source: leading silence (negative trim) then the file, head-skipped by
 * a positive trim. Returns samples actually delivered (0 = EOF). */
struct pcm_src {
	FILE *f;
	int64_t silence;		/* samples of leading silence left */
	int eof;
};

static int pcm_read(struct pcm_src *s, int16_t *dst, int want)
{
	int got = 0;
	while (got < want && s->silence > 0) {
		memset(dst + got * ACH, 0, ABPS);
		got++; s->silence--;
	}
	if (got < want && !s->eof) {
		size_t n = fread(dst + got * ACH, ABPS, want - got, s->f);
		if (n < (size_t)(want - got))
			s->eof = 1;
		got += n;
	}
	return got;
}

/* Audio pipeline state: raw PCM -> swresample -> AAC -> muxer. */
struct aenc {
	struct pcm_src pcm;
	AVCodecContext *ctx;
	AVStream *st;
	AVFormatContext *oc;
	SwrContext *swr;
	AVFrame *frame;
	AVPacket *pkt;
	int16_t *buf;
	int fsz;			/* encoder frame size (1024 for AAC) */
	int64_t pts;			/* next audio pts, 1/ARATE */
	int eof;
};

static int aenc_drain(struct aenc *a)
{
	for (;;) {
		int r = avcodec_receive_packet(a->ctx, a->pkt);
		if (r == AVERROR(EAGAIN) || r == AVERROR_EOF)
			return 0;
		if (r < 0)
			return -1;
		a->pkt->stream_index = a->st->index;
		av_packet_rescale_ts(a->pkt, a->ctx->time_base, a->st->time_base);
		if (av_interleaved_write_frame(a->oc, a->pkt) < 0)
			return -1;
	}
}

/* Encode one frame's worth of PCM (sets a->eof when the source runs dry). */
static int aenc_feed(struct aenc *a)
{
	int got = pcm_read(&a->pcm, a->buf, a->fsz);
	if (got == 0) {
		a->eof = 1;
		return 0;
	}
	a->frame->nb_samples = got;
	a->frame->format = AV_SAMPLE_FMT_FLTP;
	a->frame->sample_rate = ARATE;
	if (av_channel_layout_copy(&a->frame->ch_layout, &a->ctx->ch_layout) < 0 ||
	    av_frame_get_buffer(a->frame, 0) < 0)
		return -1;
	const uint8_t *in[1] = { (const uint8_t *)a->buf };
	if (swr_convert(a->swr, a->frame->data, got, in, got) < 0)
		return -1;
	a->frame->pts = a->pts;
	a->pts += got;
	if (avcodec_send_frame(a->ctx, a->frame) < 0)
		return -1;
	av_frame_unref(a->frame);
	return aenc_drain(a);
}

int main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "--now")) {
		struct timespec t;
		clock_gettime(CLOCK_MONOTONIC, &t);
		printf("%llu\n", (unsigned long long)t.tv_sec * 1000000000ull
				 + t.tv_nsec);
		return 0;
	}
	if (argc < 4) {
		fprintf(stderr,
			"usage: %s <video.mp4> <audio.pcm> <out.mp4> [trim_ms]\n"
			"       %s --now\n", argv[0], argv[0]);
		return 1;
	}
	const char *vpath = argv[1], *apath = argv[2], *opath = argv[3];
	long trim_ms = argc > 4 ? atol(argv[4]) : 0;

	av_log_set_level(AV_LOG_ERROR);

	/* ---- video input: locate the single H.264 stream ---- */
	AVFormatContext *ic = NULL;
	if (avformat_open_input(&ic, vpath, NULL, NULL) < 0)
		die("open %s failed\n", vpath);
	if (avformat_find_stream_info(ic, NULL) < 0)
		die("stream info failed\n");
	int vidx = -1;
	for (unsigned i = 0; i < ic->nb_streams; i++)
		if (ic->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
			vidx = i;
			break;
		}
	if (vidx < 0)
		die("no video stream in %s\n", vpath);
	AVStream *vin = ic->streams[vidx];

	/* ---- audio PCM input, trim/pad for A/V alignment ---- */
	struct aenc a = {0};
	a.pcm.f = fopen(apath, "rb");
	if (!a.pcm.f)
		die("open %s failed\n", apath);
	int64_t trim_samples = trim_ms * (ARATE / 1000);
	if (trim_samples > 0) {
		if (fseek(a.pcm.f, trim_samples * ABPS, SEEK_SET) != 0)
			die("trim seek failed\n");
	} else {
		a.pcm.silence = -trim_samples;
	}

	/* ---- output: ipod (= MP4) muxer ---- */
	g_out = opath;
	if (avformat_alloc_output_context2(&g_oc, NULL, "ipod", opath) < 0 || !g_oc)
		die("alloc output failed (ipod muxer missing?)\n");
	AVFormatContext *oc = g_oc;

	AVStream *vout = avformat_new_stream(oc, NULL);
	if (!vout || avcodec_parameters_copy(vout->codecpar, vin->codecpar) < 0)
		die("video stream copy failed\n");
	vout->time_base = vin->time_base;
#if LIBAVFORMAT_VERSION_MAJOR < 61
	/* lavf 60: the rotation display matrix is STREAM side data and is NOT
	 * carried by avcodec_parameters_copy -- losing it would flip the clip
	 * back to portrait. 61+ moved it into codecpar->coded_side_data, which
	 * the copy above already handles. */
	{
		size_t sdsz = 0;
		uint8_t *sd = av_stream_get_side_data(vin,
				AV_PKT_DATA_DISPLAYMATRIX, &sdsz);
		if (sd) {
			uint8_t *dst = av_stream_new_side_data(vout,
					AV_PKT_DATA_DISPLAYMATRIX, sdsz);
			if (!dst)
				die("side data alloc failed\n");
			memcpy(dst, sd, sdsz);
		}
	}
#endif

	/* ---- AAC encoder ---- */
	const AVCodec *acodec = avcodec_find_encoder_by_name("aac");
	if (!acodec)
		die("native aac encoder not available\n");
	a.ctx = avcodec_alloc_context3(acodec);
	if (!a.ctx)
		die("aac ctx alloc failed\n");
	a.ctx->sample_rate = ARATE;
	av_channel_layout_default(&a.ctx->ch_layout, ACH);
	a.ctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
	a.ctx->bit_rate = 160000;
	a.ctx->time_base = (AVRational){1, ARATE};
	if (oc->oformat->flags & AVFMT_GLOBALHEADER)
		a.ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
	if (avcodec_open2(a.ctx, acodec, NULL) < 0)
		die("aac open failed\n");
	a.st = avformat_new_stream(oc, NULL);
	if (!a.st || avcodec_parameters_from_context(a.st->codecpar, a.ctx) < 0)
		die("audio stream setup failed\n");
	a.st->time_base = a.ctx->time_base;
	a.oc = oc;

	AVChannelLayout inl;
	av_channel_layout_default(&inl, ACH);
	if (swr_alloc_set_opts2(&a.swr, &a.ctx->ch_layout, AV_SAMPLE_FMT_FLTP,
				ARATE, &inl, AV_SAMPLE_FMT_S16, ARATE,
				0, NULL) < 0 ||
	    swr_init(a.swr) < 0)
		die("swr init failed\n");

	a.fsz = a.ctx->frame_size > 0 ? a.ctx->frame_size : AAC_FRAME;
	a.buf = malloc((size_t)a.fsz * ABPS);
	a.frame = av_frame_alloc();
	a.pkt = av_packet_alloc();
	AVPacket *vpkt = av_packet_alloc();
	if (!a.buf || !a.frame || !a.pkt || !vpkt)
		die("oom\n");

	if (!(oc->oformat->flags & AVFMT_NOFILE) &&
	    avio_open(&oc->pb, opath, AVIO_FLAG_WRITE) < 0)
		die("open %s for write failed\n", opath);
	if (avformat_write_header(oc, NULL) < 0)
		die("write header failed\n");

	/* ---- interleaved merge ----
	 * One pending video packet at a time; audio frames are fed while their
	 * pts trails the pending video pts -- bounded memory, monotonic output. */
	int64_t vend = 0;		/* video end, input time_base */
	for (;;) {
		int r = av_read_frame(ic, vpkt);
		if (r == AVERROR_EOF)
			break;
		if (r < 0)
			die("read video failed\n");
		if (vpkt->stream_index != vidx) {
			av_packet_unref(vpkt);
			continue;
		}
		int64_t end = vpkt->pts +
			(vpkt->duration > 0 ? vpkt->duration : 0);
		if (end > vend)
			vend = end;
		while (!a.eof &&
		       av_compare_ts(a.pts, a.ctx->time_base,
				     vpkt->pts, vin->time_base) <= 0)
			if (aenc_feed(&a) < 0)
				die("audio encode failed\n");
		vpkt->stream_index = vout->index;
		av_packet_rescale_ts(vpkt, vin->time_base, vout->time_base);
		if (av_interleaved_write_frame(oc, vpkt) < 0)
			die("write video failed\n");
	}

	/* audio tail: only up to the end of the video timeline (parec keeps
	 * recording during the stop sequence; don't mux that overhang) */
	while (!a.eof &&
	       av_compare_ts(a.pts, a.ctx->time_base, vend, vin->time_base) < 0)
		if (aenc_feed(&a) < 0)
			die("audio encode failed\n");
	if (avcodec_send_frame(a.ctx, NULL) < 0 || aenc_drain(&a) < 0)
		die("audio flush failed\n");

	if (av_write_trailer(oc) < 0)
		die("write trailer failed\n");

	fprintf(stderr, "avmux: %s + %s -> %s (audio %lld ms, trim %ld ms)\n",
		vpath, apath, opath,
		(long long)(a.pts / (ARATE / 1000)), trim_ms);

	if (!(oc->oformat->flags & AVFMT_NOFILE))
		avio_closep(&oc->pb);
	avformat_free_context(oc);
	avformat_close_input(&ic);
	fclose(a.pcm.f);
	return 0;
}
