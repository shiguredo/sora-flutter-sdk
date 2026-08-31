# `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を削除する（要 CHANGE）

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-unused-from-value
- Polished: {YYYY-MM-DD}

## 目的

SDK 内部から呼び出しがなく、公開 API サーフェスとして残っている `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を削除する。対応する `SoraRole` には `fromValue` が無く方針が揃っていないため統一する。2026.1.0 リリース済のため後方互換のない変更（CHANGE）となる。

## 現状

- `lib/src/sora_codec_type.dart` の `AudioCodecType.fromValue`
- `lib/src/sora_signaling_option.dart` の `SimulcastRequestRid.fromValue`, `SpotlightRid.fromValue`

は SDK 内部から呼び出しが無い。対応する `SoraRole` には `fromValue` が無く、`VideoCodecType.fromValue` だけが `WebrtcClient.supportedVideoCodecTypes` で使われている。方針が揃っておらず、無用な API サーフェスを増やしている。

該当 3 型は `lib/sora_sdk.dart` から export されており、削除は破壊的変更（CHANGE）。

## 設計方針

- `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を削除する。
- 削除前に一段階を挟む方針を取る:
  - 次のマイナーリリース（例: 2026.2.0）で削除予定であることを `@Deprecated('Removed in 2026.2.0. Use ... instead.')` で明示する。
  - CHANGELOG に CHANGE として記載する。
  - `@Deprecated` を経てから次リリースで実削除する。
- 「必要が生じた場合に足す」方針を CODEBASE.md に明記する。
- `VideoCodecType.fromValue` は使用中のため残す。

## 完了条件

- [ ] 3 型の `fromValue` に `@Deprecated` が付与されている（削除本体は次リリース）。
- [ ] CHANGELOG に CHANGE として記載されている。
- [ ] SDK 内部からの呼び出しが無いことを再確認済み。
- [ ] `flutter analyze` と関連テストが成功する。
