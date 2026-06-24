// C ABI for the Apache-2.0 TrueHD decode core (decoder-core/src/lib.rs).
// Bridge this header into your Swift target via a module map or bridging header.
#ifndef TRUEHD_DECODER_H
#define TRUEHD_DECODER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    THD_OK = 0,
    THD_NULL_ARG = -1,
    THD_NEED_MORE_DATA = -2,
    THD_DECODE_ERROR = -3,
    THD_BUFFER_TOO_SMALL = -4,
} thd_status;

// Opaque handle.
void *truehd_decoder_new(void);

// Decode one TrueHD access unit to interleaved float PCM (the channel bed).
int truehd_decoder_decode(void *handle,
                          const uint8_t *input, size_t input_len,
                          float *out_pcm, size_t out_capacity_frames,
                          size_t *out_frames, uint32_t *out_channels);

void truehd_decoder_free(void *handle);

#ifdef __cplusplus
}
#endif

#endif // TRUEHD_DECODER_H
