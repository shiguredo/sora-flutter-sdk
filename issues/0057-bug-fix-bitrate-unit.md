# DartDoc のビットレート単位表記を kbps に修正し、有効範囲検証を追加する

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-bitrate-unit
- Polished: 2026-08-03

## 目的

`SoraConnectionConfig.audioBitRate` と `SoraConnectionConfig.videoBitRate` の単位を Sora のシグナリング仕様と一致させ、利用者が誤ったビットレートを指定することを防ぐ。

[Sora の WebSocket シグナリング仕様](https://sora-doc.shiguredo.jp/SIGNALING) では、`audio.bit_rate` の指定可能範囲は `6` 〜 `510`、`video.bit_rate` の指定可能範囲は `1` 〜 `50000` であり、いずれも単位は `kbps` である。

また devtools アプリ内でも単位の不整合（audio 側が `bps`、video 側が `kbps` と表示されている）があり、あわせて修正する。

## 現状

- `lib/src/sora_connection_config.dart` の `audioBitRate` と `videoBitRate` の DartDoc は単位を `bps` と記載している
- `lib/src/sora_connection_signaling.dart` の `_optionalAudioConnectValue` と `_optionalVideoConnectValue` は、指定された値を単位変換せず `bit_rate` として送信する
- `README.md` の設定例では `audioBitRate: 64` と `videoBitRate: 2500` を使用しており、実質的に `kbps` として扱っている
- DartDoc に従って `64000` や `2500000` を指定すると、Sora の許容範囲を超える値が送信される
- devtools アプリ内で audio 側は `bps` 表記（`devtools/lib/main.dart` や `devtools/lib/src/devtools_settings_sections.dart`）、video 側は `kbps` 表記になっており、単位表示が不整合である
- devtools のテスト `devtools/test/devtools_connection_controller_test.dart` では `audioBitRate` に `64000`（bps 想定値）が指定されている

## 再現条件

1. `audioBitRate` に `64000`、または `videoBitRate` に `2500000` を指定する
2. Sora へ接続する
3. 指定値が単位変換されず、そのまま connect メッセージの `bit_rate` に含まれる
4. Sora が想定する `kbps` と異なる値になる

## 設計方針

- 後方互換性を維持するため、`audioBitRate` と `videoBitRate` のフィールド名は変更しない
- DartDoc に単位が `kbps` であること、および指定可能範囲を明記する
  - `audioBitRate`: `6` 〜 `510` (kbps)。Sora のシグナリング仕様に基づく
  - `videoBitRate`: `1` 〜 `50000` (kbps)。同上
- `SoraConnectionConfig` のコンストラクタで指定範囲を検証し、範囲外の場合は `RangeError` を送出する。`null`（未指定）はエラーとしない
- `video: false` または `audio: false` の場合でも `audioBitRate` / `videoBitRate` の範囲検証は行う（無効時でも不正な値を検出することで、設定の意図しない誤指定を防ぐ）
- connect メッセージには指定値を単位変換せず、そのまま送信する（現状維持。ランタイム挙動は変更しない）
- `README.md` の設定例に単位を明記する
- devtools の `bps` 表記を `kbps` に修正する

## 完了条件

- [ ] `audioBitRate` と `videoBitRate` の DartDoc に単位が `kbps` と記載されている
- [ ] それぞれの指定可能範囲が DartDoc に記載されている（`6` 〜 `510`、`1` 〜 `50000`）
- [ ] 範囲外の値を指定した場合、`RangeError` が送出される
- [ ] null（未指定）は範囲検証の対象外である
- [ ] `video: false` または `audio: false` の設定時でも範囲検証が有効である
- [ ] `64` と `2500` を指定した場合、connect メッセージに同じ値が設定される
- [ ] `README.md` の設定例に単位が明記されている
- [ ] devtools の `bps` 表記が `kbps` に修正されている
- [ ] 境界値と範囲外の値を検証するテストが追加されている（`test/sora_connection_config_test.dart` 等）
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
