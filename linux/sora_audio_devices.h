#ifndef SORA_SDK_SORA_AUDIO_DEVICES_H_
#define SORA_SDK_SORA_AUDIO_DEVICES_H_

#include <flutter_linux/flutter_linux.h>

#include <string>

// PulseAudio を使って Linux の音声入出力デバイスを列挙する。
// PipeWire の PulseAudio 互換レイヤーもカバーされるため、
// 実質ほとんどのディストリビューションで動作する。
class SoraAudioDevices {
 public:
  // マイク (入力) 一覧を返す。返り値は FlValue リスト。
  // 各要素は {"deviceId": <source_name>, "label": <description>} のマップ。
  static FlValue* EnumerateInputDevices();

  // スピーカー (出力) 一覧を返す。返り値は FlValue リスト。
  // 各要素は {"deviceId": <sink_name>, "label": <description>} のマップ。
  static FlValue* EnumerateOutputDevices();

  // 既定の音声入力デバイス ID を返す。
  static std::string GetDefaultInputDeviceId();
};

#endif
