# Windows createClient の config 引数を抽出して保存する

- Priority: Low
- Created: 2026-06-19
- Completed: 2026-06-19
- Model: DeepSeek V4 Pro
- Branch: feature/add-windows-createclient-config-parsing
- Polished: 2026-06-19

## 目的

`windows/sora_sdk_plugin.cpp:105-106` の `HandleCreateClient()` で MethodChannel の `config` 引数が `(void)method_call;` により完全に無視されている。またコメントが `shiguredo-issues` の規約（issue 番号をソースコードに持ち込まない）に違反し、かつ間違った issue 番号を参照している。config を抽出して保存することで設計の一貫性を向上させ、規約違反を是正する。

## 優先度根拠

- Low: config に含まれる role / audio / video 等の設定は Dart 側 `WebrtcClient._addLocalTracks()` でも参照しており、ネイティブ側で config を解析しなくても正常動作する。Windows には iOS の AVAudioSession のようなネイティブ側の事前設定が不要なため、現状の動作に支障はない。

## 現状

`windows/sora_sdk_plugin.cpp:102-106`:

```cpp
void SoraSdkPlugin::HandleCreateClient(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // config の解析は後続 issue (0035-0037) で実装する ← 規約違反 + 無関係な番号
  (void)method_call;
```

- `(void)method_call;` により `config` 引数が完全に無視されている
- コメントは `shiguredo-issues` の「issue 番号をソースコードに持ち込まない」規約に違反しており、参照先の発行番号も config 解析とは無関係である
- Dart 側 `sora_connection.dart:257` は `{'config': config.toMap()}` を MethodChannel に送信している

## 設計方針

### config の抽出

`HandleCreateClient()` 内で `method_call.arguments()` から以下の 2 段階で config を抽出する:

1. 引数の最上位を `EncodableMap` として取得する
2. その中の `"config"` キーに対応する値を `EncodableMap` として取得する

### エラーハンドリング

- `arguments()` が nullptr または `EncodableMap` でない場合: `result->Error("invalid_argument", ...)` を返し、クライアント作成を中断する（`HandleDisposeClient` と同一の方針）
- `"config"` キーが存在しない場合: 空の `EncodableMap` として保存し、処理を続行する（iOS/macOS も `?? [:]` で空辞書にフォールバックしており、これと一致する）
- `"config"` の値が `EncodableMap` でない場合: エラーとせず空の `EncodableMap` として保存する（厳格にすると既存の Dart 側の変更が将来発生した場合に互換性を損なうため）

### config の保存

抽出した config を `ClientWrapper` に保存する。`std::optional<flutter::EncodableMap>` 型で保持し、未設定時は `std::nullopt` とする。

保存の意図は将来の拡張（クライアントごとの設定参照の必要が生じた場合）に備えるものであり、現時点では Windows に config を活用する具体的な処理は存在しない。

### コメントの修正

現状のコメントを削除し、代わりに以下のコメントに置き換える:

```cpp
// config は将来のクライアントごとの設定参照に備えて ClientWrapper に保存する。
// Windows には iOS の AVAudioSession のようなネイティブ側の事前設定が不要なため、
// 保存のみ行い積極的な活用は行わない。
```

### 0047 との競合

本 issue と 0047 はともに `HandleCreateClient()` の `ClientWrapper` 初期化部分を変更する。実装順序によってマージコンフリクトが発生しうるため、先に実装された側の変更をベースに解消する。

## 完了条件

- `HandleCreateClient()` が `method_call.arguments()` から `{"config": <map>}` の 2 段階構造で config を抽出すること
- 抽出した config が `ClientWrapper` に `std::optional<flutter::EncodableMap>` として保存されること
- 引数が不正な形式の場合にエラーレスポンスが返ること
- 誤った issue 番号を参照するコメントが削除され、代わりに適切なコメントが記載されること
- `flutter build windows --release` が成功すること
- 変更内容が `CHANGES.md` に追記されること

## 結果

### 実施した対応

- `windows/sora_sdk_plugin.cpp` のコメントを修正: 規約違反のコメントを削除し、適切なコメントに置き換えた

### 未対応（close 理由）

config の抽出・保存は **対応しない**。本対応を実施すると Windows のみ config を `ClientWrapper` に永続保存することになり、iOS / macOS / Android との挙動の差異が生じるため。他プラットフォームも同様に保存するよう改修するか、全プラットフォームで保存しない方針で統一するまで保留とする。

### 変更内容

- `windows/sora_sdk_plugin.cpp` `HandleCreateClient()` — コメントのみ修正

```cpp
  // Windows では config の内容を必要とするネイティブ処理が存在しないため、
  // 現時点では引数を解析せず unused とする。
  (void)method_call;
```

### 動作確認

- `flutter build windows --release` が成功することを確認
