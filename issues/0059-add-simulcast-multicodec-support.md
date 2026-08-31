# サイマルキャストマルチコーデックに対応する

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/add-simulcast-multicodec-support
- Polished: 2026-08-03

## 目的

Sora Flutter SDK からサイマルキャストマルチコーデックを要求し、Sora が offer の `encodings[].codec` で指定したコーデックを各送信エンコーディングへ適用できるようにする。

[Sora のサイマルキャストマルチコーデック機能](https://sora-doc.shiguredo.jp/SIMULCAST_MULTICODEC) は実験的機能であり、利用時には `simulcast: true` と `simulcast_multicodec: true` の指定、および offer の `encodings[].codec` の適用が必要である。

## 現状

- `lib/src/sora_connection_config.dart` の `SoraConnectionConfig` に `simulcastMulticodec` がない
- `lib/src/sora_connection_signaling.dart` の `_buildConnectMessage` は `simulcast_multicodec` を送信しない
- `lib/src/ffi/webrtc_client.dart` の `WebrtcClient.handleOffer` は offer の `encodings` を保持する
- `WebrtcClient._applySimulcastEncodings` は `rid`、`active`、ビットレート、縮小率、フレームレート、`scalabilityMode` を適用するが、`codec` を適用しない
- `third_party/libwebrtc-c/include/webrtc_c/api/rtp_parameters.h` には `webrtc_RtpEncodingParameters_set_codec` と `webrtc_RtpCodec` の C API があるが、`lib/src/ffi/bindings.dart` に対応する Dart FFI バインディングがない
- 認証成功時に `simulcast_multicodec` と `simulcast_codecs` が払い出されても、offer のコーデック指定が無視される

## 設計方針

### 設定とシグナリング

- `SoraConnectionConfig` に `bool? simulcastMulticodec` を追加する。DartDoc に実験的機能であることを明記する
- 指定値を `SoraConnectionConfig.toMap` と connect メッセージの `simulcast_multicodec` に反映する
- `SoraConnectionConfig` のコンストラクタで `simulcastMulticodec: true` が指定されているのに `simulcast: true` でない場合、`ArgumentError` を送出する
- `_buildConnectMessage` で `config.simulcastMulticodec` が非 null の場合は `message['simulcast_multicodec']` に設定する
- offer メッセージの `simulcast_multicodec` フラグ（Sora が認証成功時の払い出しとして offer に含める場合）が `true` の場合も、クライアントからの明示指定と同様に扱う。このフラグの取得場所は `handleOffer` 内で `message['simulcast_multicodec']` から読み取る

### FFI バインディング追加

`lib/src/ffi/bindings.dart` に以下の C API のバインディングを追加する:

- `webrtc_RtpCodec_new` / `webrtc_RtpCodec_delete`: 生成と破棄
- `webrtc_RtpCodec_set_kind` / `webrtc_RtpCodec_get_name` / `webrtc_RtpCodec_set_name` / `webrtc_RtpCodec_set_clock_rate`: コーデック情報の設定
- `webrtc_RtpCodec_get_parameters` / `std_map_string_string_set`: コーデックパラメーター操作
- `webrtc_RtpEncodingParameters_set_codec` / `webrtc_RtpEncodingParameters_get_codec`: エンコーディングへのコーデック設定と取得

### `codec` 変換

offer の `encodings[].codec` を `webrtc_RtpCodec` へ変換する手順:

1. `codec.mimeType`（例: `"video/VP8"`）から `'/'` で分割し、前半（`"video"`）から `kind` の整数値（`0` = audio, `1` = video）を決定する。後半（`"VP8"`）を `name` として `webrtc_RtpCodec_set_name` に渡す
2. `codec.clockRate` が存在する場合、`webrtc_RtpCodec_set_clock_rate` に渡す
3. `codec.sdpFmtpLine` が存在する場合、`';'` で分割し、各項目を `'='` で key と value に分割して `std_map_string_string_set` でパラメーターに追加する。value の両端の空白は trim する。`sdpFmtpLine` が空文字列や不在の場合はパラメーターなしとみなす
4. 変換後に `webrtc_RtpEncodingParameters_set_codec` でエンコーディングに設定し、送信パラメーター設定（`rtpSenderSetParameters`）完了後に `webrtc_RtpCodec_delete` で解放する

### 不正な codec の検出

以下のいずれかに該当する `codec` を「不正」とみなし、`error` イベントを通知する:
- `mimeType` が空文字列または形式不正（`'/'` を含まない）
- `mimeType` の先頭が `"video/"` でない（サイマルキャストは映像のみが対象）
- `clockRate` が指定されていない
- `mimeType` から抽出したコーデック名が既存の `supportedVideoCodecTypes` に含まれない
- `rtpSenderSetParameters` が失敗した場合

### その他

- 既存のサイマルキャストエンコーディング適用処理と、通常の単一コーデック接続を維持する
- 実験的機能であることと Sora 側の有効化が必要なことを `README.md` に明記する

## 完了条件

- [ ] `SoraConnectionConfig.simulcastMulticodec` が公開されており、DartDoc に実験的機能であることが記載されている
- [ ] `simulcastMulticodec: true` が connect メッセージの `simulcast_multicodec: true` に変換される
- [ ] `simulcastMulticodec: true` かつ `simulcast` が `true` 以外の場合、`ArgumentError` が送出される
- [ ] offer の `simulcast_multicodec` フラグも適用条件として認識される（handleOffer 内で読み取り）
- [ ] `bindings.dart` に `webrtc_RtpCodec_*`、`webrtc_RtpEncodingParameters_set_codec`、`std_map_string_string_set` のバインディングが追加されている
- [ ] `codec.mimeType` から `kind` と `name` が正しく抽出される（`video/VP8` → kind=1, name=VP8）
- [ ] `codec.clockRate` と `codec.sdpFmtpLine` が `webrtc_RtpCodec` に正しく設定される
- [ ] `webrtc_RtpCodec` が `rtpSenderSetParameters` 完了後に解放される（use-after-free がない）
- [ ] 不正な codec（空の mimeType、形式不正、video/ 以外、未対応コーデック名、clockRate 欠如）で接続エラーが通知される
- [ ] コーデックを含まない既存の `encodings` が従来どおり処理される
- [ ] `README.md` に実験的機能であることと Sora 側の有効化が必要なことが明記されている
- [ ] 実際の libwebrtc-c を利用してコーデック適用を検証するテストが追加されている
- [ ] サイマルキャストマルチコーデックを有効にした Sora との E2E テストが追加されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
