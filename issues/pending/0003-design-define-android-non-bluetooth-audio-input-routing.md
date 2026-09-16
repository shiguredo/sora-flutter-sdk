# Android の BLUETOOTH_SCO 以外の audio input routing 方針を定義する
- Priority: Medium
- Created: 2026-04-17
- Model: GPT-5.4
- Polished: 2026-06-05

## 目的

かつての issue 0093 では Android の `BLUETOOTH_SCO` に対して、communication audio routing と SCO 開始を伴う専用対応を実装した。一方で `BUILTIN_MIC`、`TYPE_USB_DEVICE`、`TYPE_USB_HEADSET` など、`BLUETOOTH_SCO` 以外の入力 type は現時点で `setPreferredInputDevice(...)` による通常経路に任せており、type ごとの routing 要件や実機差異をまだ整理していない。

`BLUETOOTH_SCO` 以外にも個別 routing が必要な type があるか、どの type までは通常経路で十分とみなすかを定義する必要がある。

## 優先度根拠

- かつての issue 0093 の対象は `BLUETOOTH_SCO` に限定しており、Bluetooth headset マイクが内蔵マイクへフォールバックする問題に対して専用対応を入れた
- Android の `AudioDeviceInfo.type` には `BUILTIN_MIC`、`TYPE_USB_DEVICE`、`TYPE_USB_HEADSET`、`TYPE_WIRED_HEADSET` など複数の入力種別がある
- 現状の SDK は `BLUETOOTH_SCO` 以外を個別判定せず、`JavaAudioDeviceModule.setPreferredInputDevice(...)` に委ねている
- type ごとに routing 要件が異なる可能性があり、特に USB / wired / vendor 固有デバイスは実機差異を考慮する必要がある

## 現状

- `BLUETOOTH_SCO` 以外の入力 type について、通常経路だけで十分かどうかの根拠が未整理
- Android の入力 type ごとの保証範囲が SDK ドキュメントと実装の両方で明確でない
- 実機差異がある type に対して、個別 routing が必要になった場合の設計方針が定まっていない

## 設計方針

1. `BUILTIN_MIC`、`TYPE_USB_DEVICE`、`TYPE_USB_HEADSET`、`TYPE_WIRED_HEADSET` など主要 type を列挙する
2. 各 type について、`setPreferredInputDevice(...)` の通常経路で十分か、追加 routing が必要かを実機で確認する
3. 追加 routing が不要な type は SDK の保証範囲として文書化する
4. 追加 routing が必要な type は別 issue に切り出し、input / output の責務分離を明確にする

## 完了条件

- Android の主要 audio input type ごとの対応方針が定義されている
- `BLUETOOTH_SCO` 専用対応と、通常経路で扱う type の境界が明確になっている
- 未対応 type や実機差異が大きい type が pending / 別 issue として整理されている
- `<DOC_REPO>/media_device.rst` の説明と実装方針が整合している

## pending 理由

`BLUETOOTH_SCO` 以外の入力 type は端末・アダプタ・OS 実装差異の影響を受けやすく、設計判断より先に実機確認が必要。
現時点では `BLUETOOTH_SCO` の不具合解消を優先し、他 type の個別 routing は設計判断待ちとして保留する。

## 解決方法

1. 主要入力 type を実機で確認する
2. 通常経路で十分な type と個別 routing が必要な type を切り分ける
3. 決定結果を SDK ドキュメントと example に反映する
