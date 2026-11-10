# 音声出力デバイスを指定できる public API を追加する
- Priority: Medium
- Created: 2026-04-20
- Model: GPT-5.4
- Polished: 2026-06-05

## 目的

現状の SDK は `MediaDevices.enumerateAudioOutputDevices()` で音声出力デバイス一覧は列挙できるが、音声出力デバイスを明示選択する SDK public API は提供していない。

Android では example 向けに `setCommunicationDevice(...)` を使った output route 制御を試しているが、Bluetooth / speaker / earpiece のような communication route では input / output が連動しやすく、`setAudioOutputDevice(...)` をそのまま SDK public API にすると期待値と保証範囲が一致しない。

iOS / iPadOS は `AVRoutePickerView`、macOS は OS / CoreAudio の既定出力に依存する側面が強く、プラットフォーム横断で「音声出力デバイスを指定する API」をどう定義するかを先に整理する必要がある。

## 優先度根拠

- `MediaDevices.enumerateAudioOutputDevices()` は既に提供している
- Android では communication route により input / output が連動し、出力先だけを厳密固定できるとは限らない
- iOS / iPadOS の出力選択は `AVRoutePickerView` を使うのが標準 UX であり、SDK が arbitrary な出力デバイス選択を public API として保証しにくい
- macOS も出力 route は OS / CoreAudio の既定出力に依存する側面が強く、入力デバイス選択と同じ粒度では API 化しにくい

## 現状

- SDK 利用者は音声出力デバイスを列挙できても、再生先切り替えの統一 API を利用できない
- Android example では platform channel で output route を変更しているが、SDK public API ではない
- プラットフォームごとに保証できる範囲が異なるため、単純な `setAudioOutputDevice(deviceId)` では API 契約が曖昧になる

## 設計方針

1. Android / iOS / iPadOS / macOS で、音声出力 route をどこまで明示指定できるかを整理する
2. SDK public API にする場合、`deviceId` を厳密固定する API なのか、route の希望を伝える API なのかを定義する
3. 出力 route が input route と連動するプラットフォームでは、その制約を API 契約としてどう表現するかを決める
4. public API 化が難しい場合は、列挙 API のみ提供し、各プラットフォームの標準 UI / 標準 route 選択へ委ねる方針も比較する

## 完了条件

- 音声出力デバイス指定 API を public に提供するかどうかの方針が決まっている
- public API にする場合、各プラットフォームで保証する範囲と保証しない範囲が定義されている
- Android の communication route 制約、iOS / iPadOS の `AVRoutePickerView`、macOS の CoreAudio 依存を踏まえた説明が整理されている
- SDK ドキュメントと example の挙動が整合している

## pending 理由

音声出力デバイス指定は、音声入力デバイス指定と違って各プラットフォームの route 制約が強く、単一の SDK public API に落とし込むには設計整理が不足している。
現時点では列挙 API と example / アプリ層での route 制御に留め、public API 化は設計判断待ちとして保留する。

## 解決方法

1. 各プラットフォームの route 制約を整理する
2. `setAudioOutputDevice` 相当 API の契約を決める
3. public API 化が難しい場合は列挙 API のみを残す
