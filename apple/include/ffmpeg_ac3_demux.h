// ffmpeg_ac3_demux.h
//
// Tiny C wrapper over libavformat that DEMUXES (does not decode) the AC-3/E-AC-3
// companion stream out of any container FFmpeg can open (MKV, M2TS, TS, MP4...).
// It opens the container, finds the AC-3/E-AC-3 audio stream, and hands back raw
// access units. No avcodec decode call is ever made here — decoding is done by
// Apple's AudioToolbox downstream. This keeps "we never decode" intact while
// using FFmpeg purely as a demuxer.
//
// Link against libavformat + libavutil (+ libavcodec for AVCodecParameters only;
// no decoder is opened). libav* is LGPL — dynamic-link it.

#ifndef FFMPEG_AC3_DEMUX_H
#define FFMPEG_AC3_DEMUX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AC3Demux AC3Demux;

typedef enum {
    AC3DEMUX_NONE = 0,
    AC3DEMUX_AC3  = 1,
    AC3DEMUX_EAC3 = 2
} AC3DemuxCodec;

// Open `url`, locate the AC-3/E-AC-3 audio stream. Returns NULL if none found or
// on error. Fills out_codec / out_channels / out_sample_rate when non-NULL.
AC3Demux *ac3demux_open(const char *url,
                        AC3DemuxCodec *out_codec,
                        int *out_channels,
                        int *out_sample_rate);

// Read the next AC-3/E-AC-3 access unit.
//   returns  1 + sets *data/*size (valid until the next call or close),
//            0 at end of stream,
//           <0 on error.
int ac3demux_next(AC3Demux *d, const uint8_t **data, int *size);

void ac3demux_close(AC3Demux *d);

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_AC3_DEMUX_H
