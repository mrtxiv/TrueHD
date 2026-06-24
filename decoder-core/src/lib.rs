//! C-ABI shim around the Apache-2.0 `truehd` decoder so Apple platforms can
//! decode Dolby TrueHD elementary streams to interleaved PCM on-device.
//!
//! Threading/ownership contract for the Swift side:
//!   * `truehd_decoder_new` returns an opaque handle (or null on failure).
//!   * `truehd_decoder_decode` is called once per TrueHD access unit. It writes
//!     interleaved f32 PCM into the caller-provided buffer and reports how many
//!     frames were produced and the channel count.
//!   * `truehd_decoder_free` releases the handle. Never call decode after free.
//!
//! This file is intentionally small and self-contained. The ONLY thing to fill
//! in is the body marked `TODO(api)` — wiring to the real `truehd` crate types.
//! Everything else (ABI, error codes, buffer protocol) is final.

use std::os::raw::{c_int, c_void};
use std::ptr;

#[repr(C)]
pub enum ThdStatus {
    Ok = 0,
    NullArg = -1,
    NeedMoreData = -2,
    DecodeError = -3,
    BufferTooSmall = -4,
}

/// Opaque decoder state handed back to Swift as a `*mut c_void`.
struct Decoder {
    // TODO(api): hold the real `truehd::Decoder` (or equivalent) here.
    // Placeholder so the scaffold type-checks without the dependency resolved.
    channels: u32,
    sample_rate: u32,
}

/// Create a decoder. Returns null on allocation/setup failure.
#[no_mangle]
pub extern "C" fn truehd_decoder_new() -> *mut c_void {
    // TODO(api): construct the real decoder. For now, a placeholder.
    let dec = Box::new(Decoder { channels: 0, sample_rate: 0 });
    Box::into_raw(dec) as *mut c_void
}

/// Decode ONE TrueHD access unit.
///
/// * `input`/`input_len` — bytes of a single TrueHD access unit.
/// * `out_pcm`/`out_capacity_frames` — caller buffer for interleaved f32 PCM,
///   capacity expressed in *frames* (one frame = `*out_channels` samples).
/// * `out_frames` — frames actually written.
/// * `out_channels` — channel count of this access unit (bed layout).
///
/// Returns a `ThdStatus`. `NeedMoreData` means feed the next access unit.
#[no_mangle]
pub extern "C" fn truehd_decoder_decode(
    handle: *mut c_void,
    input: *const u8,
    input_len: usize,
    out_pcm: *mut f32,
    out_capacity_frames: usize,
    out_frames: *mut usize,
    out_channels: *mut u32,
) -> c_int {
    if handle.is_null() || input.is_null() || out_pcm.is_null()
        || out_frames.is_null() || out_channels.is_null()
    {
        return ThdStatus::NullArg as c_int;
    }
    let _dec = unsafe { &mut *(handle as *mut Decoder) };
    let _bytes = unsafe { std::slice::from_raw_parts(input, input_len) };
    let _out = unsafe { std::slice::from_raw_parts_mut(out_pcm, out_capacity_frames) };

    // TODO(api): call the real `truehd` decode here:
    //   1. parse/restart-sync the access unit,
    //   2. run lossless MLP reconstruction to PCM (the BED — not Atmos objects),
    //   3. interleave into `_out`, set *out_frames and *out_channels,
    //   4. honor BufferTooSmall if out_capacity_frames is insufficient.
    unsafe {
        *out_frames = 0;
        *out_channels = 0;
    }
    ThdStatus::NeedMoreData as c_int
}

/// Free a decoder created by `truehd_decoder_new`.
#[no_mangle]
pub extern "C" fn truehd_decoder_free(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle as *mut Decoder)); }
    }
}

// Keep the placeholder fields referenced so -D warnings stays clean.
#[allow(dead_code)]
fn _touch(d: &Decoder) -> (u32, u32) { (d.channels, d.sample_rate) }
const _: *const c_void = ptr::null();
