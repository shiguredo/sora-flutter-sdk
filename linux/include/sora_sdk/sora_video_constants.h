#ifndef SORA_SDK_VIDEO_CONSTANTS_H_
#define SORA_SDK_VIDEO_CONSTANTS_H_

// libyuv の FOURCC 定数。
// webrtc-c の libyuv バイナリはビッグエンディアン FOURCC エンコーディングを
// 使用しているため、MSB から a, b, c, d の順で定義する。
#define SORA_LIBYUV_FOURCC_RGBA                                           \
  ((uint32_t)('R') << 24 | (uint32_t)('G') << 16 | (uint32_t)('B') << 8 | \
   (uint32_t)('A'))

#endif
