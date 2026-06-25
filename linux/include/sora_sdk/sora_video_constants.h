#ifndef SORA_SDK_VIDEO_CONSTANTS_H_
#define SORA_SDK_VIDEO_CONSTANTS_H_

// libyuv の FOURCC_RGBA 値 (R | G << 8 | B << 16 | A << 24)
// <webrtc_c/libyuv.h> が定数を提供していないため自前で定義する
#define SORA_LIBYUV_FOURCC_RGBA \
    ((uint32_t)('R') | ((uint32_t)('G') << 8) | ((uint32_t)('B') << 16) | ((uint32_t)('A') << 24))

#endif
