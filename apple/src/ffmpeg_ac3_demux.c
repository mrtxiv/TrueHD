// ffmpeg_ac3_demux.c — demux-only AC-3/E-AC-3 extraction via libavformat.
//
// IMPORTANT: this file calls NO decode functions (no avcodec_send_packet /
// avcodec_receive_frame). It only demuxes. Apple's AudioToolbox decodes the
// packets it returns.

#include "ffmpeg_ac3_demux.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>   // for AVCodecParameters / AV_CODEC_ID_* only
#include <stdlib.h>

struct AC3Demux {
    AVFormatContext *fmt;
    int stream_index;
    AVPacket *pkt;
};

AC3Demux *ac3demux_open(const char *url,
                        AC3DemuxCodec *out_codec,
                        int *out_channels,
                        int *out_sample_rate) {
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, url, NULL, NULL) < 0) {
        return NULL;
    }
    if (avformat_find_stream_info(fmt, NULL) < 0) {
        avformat_close_input(&fmt);
        return NULL;
    }

    int idx = -1;
    AC3DemuxCodec codec = AC3DEMUX_NONE;
    for (unsigned i = 0; i < fmt->nb_streams; i++) {
        AVCodecParameters *p = fmt->streams[i]->codecpar;
        if (p->codec_type != AVMEDIA_TYPE_AUDIO) continue;
        if (p->codec_id == AV_CODEC_ID_AC3)  { idx = (int)i; codec = AC3DEMUX_AC3;  break; }
        if (p->codec_id == AV_CODEC_ID_EAC3) { idx = (int)i; codec = AC3DEMUX_EAC3; break; }
    }

    // No separate AC-3/E-AC-3 stream. (A TrueHD-only track does not expose its
    // embedded AC-3 core as a stream here — that would need a separate track or
    // dedicated core extraction.)
    if (idx < 0) {
        avformat_close_input(&fmt);
        return NULL;
    }

    AVCodecParameters *p = fmt->streams[idx]->codecpar;
    if (out_codec)       *out_codec       = codec;
    // FFmpeg 5.1+: ch_layout.nb_channels. For older FFmpeg use p->channels.
    if (out_channels)    *out_channels    = p->ch_layout.nb_channels;
    if (out_sample_rate) *out_sample_rate = p->sample_rate;

    AC3Demux *d = (AC3Demux *)calloc(1, sizeof(AC3Demux));
    if (!d) { avformat_close_input(&fmt); return NULL; }
    d->fmt = fmt;
    d->stream_index = idx;
    d->pkt = av_packet_alloc();
    if (!d->pkt) { avformat_close_input(&fmt); free(d); return NULL; }
    return d;
}

int ac3demux_next(AC3Demux *d, const uint8_t **data, int *size) {
    if (!d) return -1;
    av_packet_unref(d->pkt);
    for (;;) {
        int r = av_read_frame(d->fmt, d->pkt);
        if (r == AVERROR_EOF) return 0;
        if (r < 0) return r;
        if (d->pkt->stream_index == d->stream_index) {
            *data = d->pkt->data;
            *size = d->pkt->size;
            return 1;            // caller copies before the next call
        }
        av_packet_unref(d->pkt); // not our stream; keep reading
    }
}

void ac3demux_close(AC3Demux *d) {
    if (!d) return;
    if (d->pkt) av_packet_free(&d->pkt);
    if (d->fmt) avformat_close_input(&d->fmt);
    free(d);
}
