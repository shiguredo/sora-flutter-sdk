#include "sora_audio_devices.h"

#include <flutter/encodable_value.h>

#include <mmdeviceapi.h>
#include <propsys.h>

#include <string>

#include <wrl/client.h>

// PKEY_Device_FriendlyName の手動定義。
// functiondiscoverykeys.h / propkey.h は Windows SDK 10.0.26100
// との互換性に問題があるため、必要な定数のみを直接定義する。
// {0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}}, 14
static const PROPERTYKEY PKEY_Device_FriendlyName = {
    {0xa45c254e,
     0xdf1c,
     0x4efd,
     {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    14};

using Microsoft::WRL::ComPtr;

namespace {

// LPWSTR を UTF-8 std::string に変換する
// 変換に失敗した場合は空文字列を返す
std::string WideToUTF8(LPCWSTR wide) {
  int size =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return "";
  }
  std::string result(size - 1, '\0');
  if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, &result[0], size, nullptr,
                          nullptr) <= 0) {
    return "";
  }
  return result;
}

flutter::EncodableMap DeviceToEncodableMap(IMMDevice* device) {
  flutter::EncodableMap map;

  LPWSTR id = nullptr;
  if (SUCCEEDED(device->GetId(&id))) {
    std::string device_id = WideToUTF8(id);
    CoTaskMemFree(id);
    if (!device_id.empty()) {
      map[flutter::EncodableValue("deviceId")] =
          flutter::EncodableValue(device_id);
      map[flutter::EncodableValue("label")] =
          flutter::EncodableValue(device_id);
    }
  }

  ComPtr<IPropertyStore> store;
  if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store))) {
    PROPVARIANT var;
    PropVariantInit(&var);
    if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &var)) &&
        var.vt == VT_LPWSTR) {
      std::string label = WideToUTF8(var.pwszVal);
      if (!label.empty()) {
        map[flutter::EncodableValue("label")] = flutter::EncodableValue(label);
      }
    }
    PropVariantClear(&var);
  }

  return map;
}

flutter::EncodableList EnumerateDevices(EDataFlow data_flow) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool com_initialized = SUCCEEDED(hr);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    OutputDebugStringA(("SoraAudioDevices: CoInitializeEx failed: hr=" +
                        std::to_string(static_cast<int>(hr)))
                           .c_str());
    return flutter::EncodableList();
  }

  flutter::EncodableList devices;
  do {
    ComPtr<IMMDeviceEnumerator> enumerator;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) {
      OutputDebugStringA(("SoraAudioDevices: CoCreateInstance "
                          "IMMDeviceEnumerator failed: hr=" +
                          std::to_string(static_cast<int>(hr)))
                             .c_str());
      break;
    }

    ComPtr<IMMDeviceCollection> collection;
    hr = enumerator->EnumAudioEndpoints(data_flow, DEVICE_STATE_ACTIVE,
                                        &collection);
    if (FAILED(hr)) {
      OutputDebugStringA(("SoraAudioDevices: EnumAudioEndpoints failed: hr=" +
                          std::to_string(static_cast<int>(hr)))
                             .c_str());
      break;
    }

    UINT count = 0;
    hr = collection->GetCount(&count);
    if (FAILED(hr)) {
      OutputDebugStringA(("SoraAudioDevices: GetCount failed: hr=" +
                          std::to_string(static_cast<int>(hr)))
                             .c_str());
      break;
    }
    if (count == 0) {
      break;
    }

    for (UINT i = 0; i < count; i++) {
      ComPtr<IMMDevice> device;
      if (SUCCEEDED(collection->Item(i, &device))) {
        flutter::EncodableMap map = DeviceToEncodableMap(device.Get());
        if (map.find(flutter::EncodableValue("deviceId")) != map.end()) {
          devices.push_back(flutter::EncodableValue(map));
        }
      }
    }
  } while (false);

  if (com_initialized) {
    CoUninitialize();
  }
  return devices;
}

}  // namespace

flutter::EncodableList SoraAudioDevices::EnumerateInputDevices() {
  return EnumerateDevices(eCapture);
}

flutter::EncodableList SoraAudioDevices::EnumerateOutputDevices() {
  return EnumerateDevices(eRender);
}

std::string SoraAudioDevices::GetDefaultInputDeviceId() {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool com_initialized = SUCCEEDED(hr);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    OutputDebugStringA(("SoraAudioDevices: CoInitializeEx failed: hr=" +
                        std::to_string(static_cast<int>(hr)))
                           .c_str());
    return "";
  }

  std::string device_id;
  do {
    ComPtr<IMMDeviceEnumerator> enumerator;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) {
      OutputDebugStringA(("SoraAudioDevices: CoCreateInstance "
                          "IMMDeviceEnumerator failed: hr=" +
                          std::to_string(static_cast<int>(hr)))
                             .c_str());
      break;
    }

    ComPtr<IMMDevice> device;
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    if (FAILED(hr)) {
      OutputDebugStringA(
          ("SoraAudioDevices: GetDefaultAudioEndpoint failed: hr=" +
           std::to_string(static_cast<int>(hr)))
              .c_str());
      break;
    }

    LPWSTR id = nullptr;
    hr = device->GetId(&id);
    if (FAILED(hr)) {
      OutputDebugStringA(("SoraAudioDevices: device->GetId failed: hr=" +
                          std::to_string(static_cast<int>(hr)))
                             .c_str());
      break;
    }

    device_id = WideToUTF8(id);
    CoTaskMemFree(id);
  } while (false);

  if (com_initialized) {
    CoUninitialize();
  }
  return device_id;
}
