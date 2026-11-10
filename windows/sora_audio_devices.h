#ifndef SORA_SDK_SORA_AUDIO_DEVICES_H_
#define SORA_SDK_SORA_AUDIO_DEVICES_H_

#include <flutter/encodable_value.h>

#include <string>

class SoraAudioDevices {
 public:
  static flutter::EncodableList EnumerateInputDevices();
  static flutter::EncodableList EnumerateOutputDevices();
  static std::string GetDefaultInputDeviceId();
};

#endif
