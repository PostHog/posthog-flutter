#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "PostHog.h"
#import "ph_backward_references_enc.h"
#import "ph_bit_reader_utils.h"
#import "ph_bit_writer_utils.h"
#import "ph_color_cache_utils.h"
#import "ph_common_dec.h"
#import "ph_common_sse2.h"
#import "ph_common_sse41.h"
#import "ph_cost_enc.h"
#import "ph_cpu.h"
#import "ph_decode.h"
#import "ph_dsp.h"
#import "ph_encode.h"
#import "ph_endian_inl_utils.h"
#import "ph_filters_utils.h"
#import "ph_format_constants.h"
#import "ph_histogram_enc.h"
#import "ph_huffman_encode_utils.h"
#import "ph_huffman_utils.h"
#import "ph_lossless.h"
#import "ph_lossless_common.h"
#import "ph_mux.h"
#import "ph_muxi.h"
#import "ph_mux_types.h"
#import "ph_neon.h"
#import "ph_palette.h"
#import "ph_quant.h"
#import "ph_quant_levels_utils.h"
#import "ph_random_utils.h"
#import "ph_rescaler_utils.h"
#import "ph_sharpyuv.h"
#import "ph_sharpyuv_cpu.h"
#import "ph_sharpyuv_csp.h"
#import "ph_sharpyuv_dsp.h"
#import "ph_sharpyuv_gamma.h"
#import "ph_thread_utils.h"
#import "ph_types.h"
#import "ph_utils.h"
#import "ph_vp8i_dec.h"
#import "ph_vp8i_enc.h"
#import "ph_vp8li_dec.h"
#import "ph_vp8li_enc.h"
#import "ph_vp8_dec.h"
#import "ph_webpi_dec.h"
#import "ph_yuv.h"

FOUNDATION_EXPORT double PostHogVersionNumber;
FOUNDATION_EXPORT const unsigned char PostHogVersionString[];

