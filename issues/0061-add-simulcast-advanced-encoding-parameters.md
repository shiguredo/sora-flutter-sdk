# サイマルキャストの高度な encoding パラメーターを適用する

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/add-simulcast-advanced-encoding-parameters
- Polished: 2026-08-03

## 目的

Sora の offer に含まれるサイマルキャストの高度な encoding パラメーターを、libwebrtc の `RTCRtpEncodingParameters` へ適用できるようにする。

[Sora のサイマルキャスト機能](https://sora-doc.shiguredo.jp/SIMULCAST) では、`scaleResolutionDownTo`、`adaptivePtime`、`priority`、`networkPriority` などの高度なカスタム encoding を指定できる。

## 現状

- `WebrtcClient._applySimulcastEncodings` は `rid`、`active`、ビットレート、`scaleResolutionDownBy`、`maxFramerate`、`scalabilityMode` を適用する
- `scaleResolutionDownTo`、`adaptivePtime`、`priority`、`networkPriority` は offer に含まれていても無視される
- libwebrtc-c には各パラメーターを設定する C API が存在する
- `lib/src/ffi/bindings.dart` には対応する Dart FFI バインディングがない
- sora.conf の `simulcast_encodings_file` や認証成功時の払い出しで高度な encoding を指定しても、SDK では適用されない

## 設計方針

- `lib/src/ffi/bindings.dart` に次の C API のバインディングを追加する
  - `webrtc_Resolution` の生成、破棄、幅、高さの操作
  - `scale_resolution_down_to` の取得と設定
  - `adaptive_ptime` の取得と設定
  - `bitrate_priority` の取得と設定
  - `network_priority` の取得と設定
  - `webrtc_Priority_kVeryLow` / `kLow` / `kMedium` / `kHigh` 定数
- `scaleResolutionDownTo` の `maxWidth` と `maxHeight` を正の整数として検証し、`webrtc_Resolution` に変換する
- `maxWidth` と `maxHeight` の両方が指定されている場合のみ `scaleResolutionDownTo` を適用し、片方のみの場合は適用しない（Sora の仕様）。片方のみの場合は `scaleResolutionDownBy` が指定されていれば従来どおり適用する
- `scaleResolutionDownTo` と `scaleResolutionDownBy` が同時に指定された場合は、Sora の仕様どおり `scaleResolutionDownTo` を優先する
- `adaptivePtime` を boolean として適用する
- `networkPriority` の `very-low`、`low`、`medium`、`high` を `webrtc_Priority_kVeryLow` / `kLow` / `kMedium` / `kHigh` の値へ変換する
- `priority` の `very-low`、`low`、`medium`、`high` を bitrate priority (double) へ変換する。変換値は `very-low` = 0.5 / `low` = 1.0 / `medium` = 2.0 / `high` = 4.0 とし、getter API で適用結果を検証する（libwebrtc の `api/rtp_parameters.h` のコメントと Chromium の `rtc_rtp_sender.cc` の `PriorityToDouble` がこの変換値を定義している。W3C 仕様は数値変換を定義していない）
- 不正な型、未対応の優先度、範囲外の値を黙って無視せず、理由が分かる接続エラーとして通知する。通知は既存の error イベント規約 (`emitState` の error type) に沿い、エラー通知後もネゴシエーションは既存どおり継続する。検証エラーが発生した場合は適用処理全体を中断し、`rtpSenderSetParameters` を呼ばずに既存の encoding を維持する
- 新規 4 パラメーターの検証は本 issue の適用対象のみとし、既存パラメーター (`maxBitrate` 等) の既存挙動（クランプ・スキップ）は変更しない
- 適用は既存の適用経路に沿って setRemoteDescription 完了後に 1 回行う。一時的に生成したネイティブオブジェクト (`webrtc_Resolution` 等) を確実に解放する
- `lib/src/ffi/webrtc_client.dart` の `_applySimulcastEncodings` 直上の stale コメント（「setRemoteDescription の前後で 2 回呼ぶ」）を実装に合わせて修正する
- re-offer では既存挙動どおり encodings を適用しない（適用対象は初回 offer のみ）
- `encodings[].codec` の適用は `0059-add-simulcast-multicodec-support.md` の範囲とし、本 issue では扱わない
- 対応パラメーターとプラットフォーム上の制約 (`scaleResolutionDownTo` は Chrome 131 / Edge 131 以降のみ、`adaptivePtime` / `priority` / `networkPriority` は Chrome のみ。Sora の仕様) を `README.md` に記載する。`adaptivePtime` は Chromium では audio 専用のため、video の simulcast encodings では実効しない可能性がある旨も併記する

## 完了条件

- [ ] `scaleResolutionDownTo.maxWidth` と `maxHeight` が `RTCRtpEncodingParameters` に適用される
- [ ] `maxWidth` と `maxHeight` の両方が指定された場合のみ `scaleResolutionDownTo` が適用される
- [ ] `scaleResolutionDownTo` が `scaleResolutionDownBy` より優先される
- [ ] `adaptivePtime` の `true` と `false` が適用される
- [ ] `priority` の 4 種類の値が bitrate priority (`very-low` = 0.5 / `low` = 1.0 / `medium` = 2.0 / `high` = 4.0) に変換される
- [ ] `networkPriority` の 4 種類の値が `webrtc_Priority_k*` の値に変換される
- [ ] 未指定のパラメーターは既存値を変更しない
- [ ] 不正な型、範囲外の値、未対応の優先度で理由が分かるエラーが通知される
- [ ] 実際の libwebrtc-c と getter API を利用して適用結果を検証するテストが追加されている（`adaptivePtime` の `false` と `priority` の `low` は getter の値が未設定時と同値になるため、設定前の値との比較で検証する）
- [ ] Sora のカスタム encoding を利用した E2E テストが追加されている
- [ ] ネイティブオブジェクトの解放漏れがない
- [ ] 既存のサイマルキャスト処理と `0059` の `codec` 適用を妨げない
- [ ] `README.md` に対応パラメーターとプラットフォーム上の制約が記載されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
