# DegradationPreference に対応する

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/add-degradation-preference
- Polished: {YYYY-MM-DD}

## 目的

回線が不安定になったときに映像エンコーダーが解像度とフレームレートのどちらを優先して品質を下げるかを、利用者が指定できるようにする。

Sora の iOS SDK / Android SDK / Unity SDK / Python SDK は DegradationPreference に対応しており、Flutter SDK にも同等の設定を提供する。

## 現状

- `lib/src/ffi/bindings.dart` に `webrtc_DegradationPreference_*` の 4 定数と `webrtc_RtpParameters_get_degradation_preference` / `webrtc_RtpParameters_set_degradation_preference` のバインディングがない
- `lib/src/sora_connection_config.dart` に DegradationPreference を指定するフィールドがなく、enum も存在しない
- `lib/src/ffi/webrtc_client.dart` の `_applySimulcastEncodings` は `_videoRtpSender` の `RtpParameters` に simulcast encodings を適用するが、degradation_preference は適用しない
- 送信側パラメーターを適用する経路は simulcast encodings がある場合の `applyEncodings` コールバックのみで、simulcast を使わない場合は何も適用されない
- libwebrtc-c には定数と getter / setter が実装済み (`third_party/libwebrtc-c/include/webrtc_c/api/rtp_parameters.h`)

## 設計方針

- `DegradationPreference` enum を新規ファイル `lib/src/sora_degradation_preference.dart` に追加し、`disabled` / `maintainFramerate` / `maintainResolution` / `balanced` の 4 値を持たせる。`lib/sora_sdk.dart` から export する
- enum は値を持たず、`WebrtcConstants` の定数への対応は適用側で行う。定数はプラットフォームごとに C 側で定義される `extern const int` を `_lookup` で読む既存方針に合わせる
- `WebrtcConstants` に `degradationPreferenceDisabled` / `degradationPreferenceMaintainFramerate` / `degradationPreferenceMaintainResolution` / `degradationPreferenceBalanced` を `_lookup` で追加する
- `LibWebrtcC` に `rtpParametersGetDegradationPreference` (out_has / out_value) と `rtpParametersSetDegradationPreference` (has / value) を、既存の `rtpEncodingParametersGetMaxBitrateBps` 等と同じ形で追加する
- `SoraConnectionConfig` に `DegradationPreference? degradationPreference` を追加する。これは WebRTC の送信側パラメーターであり Sora サーバーへ送る connect メッセージのフィールドではないため、connect メッセージの payload には含めない。`useAudioDevice` と同様に `toMap()` へは含める
- 適用対象は `_videoRtpSender` のみとし、音声 sender には適用しない (Sora の他 SDK と同じ)
- 適用タイミングは `setRemoteDescription` の完了後とする。`_applySimulcastEncodings` を encodings と degradationPreference の両方を受け取る送信側パラメーター適用処理へ一般化し、simulcast を使わず degradationPreference だけを指定する場合でも呼ばれるようにする。`rtpSenderSetParameters` の呼び出しは 1 回に抑える
- `setRemoteDescription` は degradation_preference をリセットしうるため、re-offer (`handleReOffer`) でも再適用する。re-offer で simulcast encodings を適用しない既存挙動は変えない
- 未指定の場合は `degradation_preference` を変更しない
- `rtpSenderSetParameters` がエラーを返した場合は simulcast と同じ `_emitDebug` 経路で理由を通知し、接続は継続する
- `README.md` の `SoraConnectionConfig` 設定例と対応範囲表に DegradationPreference を追記する

## 完了条件

- [ ] `DegradationPreference` の 4 値が `webrtc_DegradationPreference_*` に対応している
- [ ] `SoraConnectionConfig.degradationPreference` で指定した値が `_videoRtpSender` の `RtpParameters.degradation_preference` に適用される
- [ ] simulcast の有無にかかわらず適用される
- [ ] re-offer 後も適用が維持される
- [ ] 未指定の場合は値が変更されない
- [ ] `rtpSenderSetParameters` のエラーで接続が失敗せず、理由が分かる通知が出る
- [ ] `webrtc_RtpParameters_get_degradation_preference` で適用結果を検証するテストが追加されている
- [ ] `README.md` に追記されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
