// Dart 側から PCM データを注入可能なカスタム AudioDeviceModule。
//
// libwebrtc-c の webrtc_CreateAudioDeviceModuleWithCallback を使って
// vtable 問題を回避しながらカスタム ADM を実装する。

#include <cstdint>

#include <webrtc_c.h>
#include <webrtc_c/api/audio/audio_device.h>
#include <webrtc_c/api/audio/audio_device_defines.h>

// RegisterAudioCallback で受け取った transport を保存する。
// この transport に対して Dart 側が RecordedDataIsAvailable を呼ぶ。
static struct webrtc_AudioTransport* g_push_audio_transport = nullptr;
static int g_recording = 0;

static int32_t adm_active_audio_layer(int* audio_layer, void* user_data) {
  *audio_layer = 0;  // kDummyAudio
  return 0;
}

static int32_t adm_register_audio_callback(
    struct webrtc_AudioTransport* audio_transport, void* user_data) {
  g_push_audio_transport = audio_transport;
  return 0;
}

static int32_t adm_init(void* user_data) { return 0; }
static int32_t adm_terminate(void* user_data) { return 0; }
static int adm_initialized(void* user_data) { return 1; }

static int16_t adm_recording_devices(void* user_data) { return 1; }

static int32_t adm_recording_device_name(uint16_t index, char name[128],
                                         char guid[128], void* user_data) {
  return 0;
}

static int32_t adm_set_recording_device(uint16_t index, void* user_data) {
  return 0;
}

static int32_t adm_recording_is_available(int* available, void* user_data) {
  *available = 1;
  return 0;
}

static int32_t adm_init_recording(void* user_data) { return 0; }
static int adm_recording_is_initialized(void* user_data) { return 1; }

static int32_t adm_start_recording(void* user_data) {
  g_recording = 1;
  return 0;
}

static int32_t adm_stop_recording(void* user_data) {
  g_recording = 0;
  return 0;
}

static int adm_recording(void* user_data) { return g_recording; }

static int32_t adm_init_microphone(void* user_data) { return 0; }
static int adm_microphone_is_initialized(void* user_data) { return 1; }

static int32_t adm_stereo_recording_is_available(int* available,
                                                  void* user_data) {
  *available = 0;
  return 0;
}

static int32_t adm_set_stereo_recording(int enable, void* user_data) {
  return 0;
}

static int32_t adm_stereo_recording(int* enabled, void* user_data) {
  *enabled = 0;
  return 0;
}

static int32_t adm_playout_delay(uint16_t* delay_ms, void* user_data) {
  *delay_ms = 0;
  return 0;
}

static int adm_get_record_audio_parameters(
    struct webrtc_AudioParameters_unique** out_params, void* user_data) {
  *out_params = nullptr;
  return -1;
}

static int adm_get_playout_audio_parameters(
    struct webrtc_AudioParameters_unique** out_params, void* user_data) {
  *out_params = nullptr;
  return -1;
}

static void adm_on_destroy(void* user_data) {
  g_push_audio_transport = nullptr;
  g_recording = 0;
}

extern "C" {

__declspec(dllexport) struct webrtc_AudioDeviceModule_refcounted* sora_create_push_audio_device() {
  // 必要なコールバックだけ設定し、残りは NULL → AudioDeviceModuleImpl が
  // デフォルト値で補完する。
  struct webrtc_AudioDeviceModule_cbs cbs;
  __builtin_memset(&cbs, 0, sizeof(cbs));
  cbs.ActiveAudioLayer = adm_active_audio_layer;
  cbs.RegisterAudioCallback = adm_register_audio_callback;
  cbs.Init = adm_init;
  cbs.Terminate = adm_terminate;
  cbs.Initialized = adm_initialized;
  cbs.RecordingDevices = adm_recording_devices;
  cbs.RecordingDeviceName = adm_recording_device_name;
  cbs.SetRecordingDevice = adm_set_recording_device;
  cbs.RecordingIsAvailable = adm_recording_is_available;
  cbs.InitRecording = adm_init_recording;
  cbs.RecordingIsInitialized = adm_recording_is_initialized;
  cbs.StartRecording = adm_start_recording;
  cbs.StopRecording = adm_stop_recording;
  cbs.Recording = adm_recording;
  cbs.InitMicrophone = adm_init_microphone;
  cbs.MicrophoneIsInitialized = adm_microphone_is_initialized;
  cbs.StereoRecordingIsAvailable = adm_stereo_recording_is_available;
  cbs.SetStereoRecording = adm_set_stereo_recording;
  cbs.StereoRecording = adm_stereo_recording;
  cbs.PlayoutDelay = adm_playout_delay;
  cbs.GetRecordAudioParameters = adm_get_record_audio_parameters;
  cbs.GetPlayoutAudioParameters = adm_get_playout_audio_parameters;
  cbs.OnDestroy = adm_on_destroy;
  return webrtc_CreateAudioDeviceModuleWithCallback(&cbs, nullptr);
}

__declspec(dllexport) void sora_push_audio_on_data(const int16_t* audio_data, int samples,
                              int channels, int sample_rate) {
  auto* transport = g_push_audio_transport;
  if (transport == nullptr) {
    return;
  }
  uint32_t new_mic_level = 0;
  int64_t capture_time_ns = 0;
  webrtc_AudioTransport_RecordedDataIsAvailable(
      transport, audio_data, samples, sizeof(int16_t), channels, sample_rate,
      0, 0, 0, 0, &new_mic_level, &capture_time_ns);
}

}  // extern "C"
